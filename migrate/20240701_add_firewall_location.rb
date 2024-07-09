# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:firewall) do
      add_column :location, :text, null: false
    end
  end
end
