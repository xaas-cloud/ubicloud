# frozen_string_literal: true

require "net/ssh"
require_relative "../model"

class Sshable < Sequel::Model
  # We need to unrestrict primary key so Sshable.new(...).save_changes works
  # in sshable_spec.rb.
  unrestrict_primary_key

  plugin ResourceMethods, encrypted_columns: [:raw_private_key_1, :raw_private_key_2]

  SSH_CONNECTION_ERRORS = [
    Net::SSH::Disconnect,
    Net::SSH::ConnectionTimeout,
    Errno::ECONNRESET,
    Errno::ECONNREFUSED,
    IOError
  ].freeze

  class SshError < StandardError
    attr_reader :stdout, :stderr, :exit_code, :exit_signal

    def initialize(cmd, stdout, stderr, exit_code, exit_signal)
      @exit_code = exit_code
      @exit_signal = exit_signal
      @stdout = stdout
      @stderr = stderr
      super("command exited with an error: " + cmd)
    end
  end

  def keys
    [raw_private_key_1, raw_private_key_2].compact.map {
      SshKey.from_binary(it)
    }
  end

  def self.repl?
    REPL
  end

  def repl?
    self.class.repl?
  end

  def cmd(cmd, stdin: nil, log: true)
    start = Time.now
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = nil
    exit_signal = nil
    channel_duration = nil

    begin
      connect.open_channel do |ch|
        channel_duration = Time.now - start
        ch.exec(cmd) do |ch, success|
          ch.on_data do |ch, data|
            $stderr.write(data) if repl?
            stdout.write(data)
          end

          ch.on_extended_data do |ch, type, data|
            $stderr.write(data) if repl?
            stderr.write(data)
          end

          ch.on_request("exit-status") do |ch2, data|
            exit_code = data.read_long
          end

          ch.on_request("exit-signal") do |ch2, data|
            exit_signal = data.read_long
          end
          ch.send_data stdin
          ch.eof!
          ch.wait
        end
      end.wait
    rescue
      invalidate_cache_entry
      raise
    end

    stdout_str = stdout.string.freeze
    stderr_str = stderr.string.freeze

    if log
      Clog.emit("ssh cmd execution") do
        finish = Time.now
        embed = {start:, finish:, cmd:, exit_code:, exit_signal:, ubid:, duration: finish - start}

        # Suppress large outputs to avoid annoyance in duplication
        # when in the REPL.  In principle, the user of the REPL could
        # read the Clog output and the feature of printing output in
        # real time to $stderr could be removed, but when supervising
        # a tty, I've found it can be useful to see data arrive in
        # real time from SSH.
        unless repl?
          embed[:stderr] = stderr_str
          embed[:stdout] = stdout_str
        end
        embed[:channel_duration] = channel_duration
        embed[:connect_duration] = @connect_duration if @connect_duration
        {ssh: embed}
      end
    end

    fail SshError.new(cmd, stdout_str, stderr.string.freeze, exit_code, exit_signal) unless exit_code.zero?
    stdout_str
  end

  def d_check(unit_name)
    cmd("common/bin/daemonizer2 check #{unit_name.shellescape}")
  end

  def d_clean(unit_name)
    cmd("common/bin/daemonizer2 clean #{unit_name.shellescape}")
  end

  def d_run(unit_name, *run_command, stdin: nil, log: true)
    cmd("common/bin/daemonizer2 run #{unit_name.shellescape} #{Shellwords.join(run_command)}", stdin:, log:)
  end

  def d_restart(unit_name)
    cmd("common/bin/daemonizer2 restart #{unit_name}")
  end

  # A huge number of settings are needed to isolate net-ssh from the
  # host system and provide some anti-hanging assurance (keepalive,
  # timeout).
  COMMON_SSH_ARGS = {non_interactive: true, timeout: 10,
                     user_known_hosts_file: [], global_known_hosts_file: [],
                     verify_host_key: :accept_new, keys: [], key_data: [], use_agent: false,
                     keepalive: true, keepalive_interval: 3, keepalive_maxcount: 5}.freeze

  def connect
    Thread.current[:clover_ssh_cache] ||= {}

    # Cache hit.
    if (sess = Thread.current[:clover_ssh_cache][[host, unix_user]])
      return sess
    end

    # Cache miss.
    start = Time.now
    sess = start_fresh_session
    @connect_duration = Time.now - start
    Thread.current[:clover_ssh_cache][[host, unix_user]] = sess
    sess
  end

  def start_fresh_session(&block)
    Net::SSH.start(host, unix_user, **COMMON_SSH_ARGS, key_data: keys.map(&:private_key), &block)
  end

  def invalidate_cache_entry
    Thread.current[:clover_ssh_cache]&.delete([host, unix_user])
  end

  def available?
    cmd("true") && true
  rescue *SSH_CONNECTION_ERRORS
    false
  end

  def self.reset_cache
    return [] unless (cache = Thread.current[:clover_ssh_cache])

    cache.filter_map do |key, sess|
      sess.close
      nil
    rescue => e
      e
    ensure
      cache.delete(key)
    end
  end
end

# Table: sshable
# Columns:
#  id                | uuid | PRIMARY KEY
#  host              | text |
#  raw_private_key_1 | text |
#  raw_private_key_2 | text |
#  unix_user         | text | NOT NULL DEFAULT 'rhizome'::text
# Indexes:
#  sshable_pkey     | PRIMARY KEY btree (id)
#  sshable_host_key | UNIQUE btree (host)
# Referenced By:
#  vm_host | vm_host_id_fkey | (id) REFERENCES sshable(id)
