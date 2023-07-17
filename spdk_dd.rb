require "openssl"
require "json"

data_encryption_key = OpenSSL::Cipher.new("aes-256-xts").random_key.unpack1("H*")

encryption_key = {
  cipher: "AES_XTS",
  key: data_encryption_key[..63],
  key2: data_encryption_key[64..]
}

bdev_conf = [{
  method: "bdev_aio_create",
  params: {
    name: "aio0",
    block_size: 512,
    filename: "spdk-encrypted-image",
    readonly: false
  }
}]

bdev_conf.append({
  method: "bdev_crypto_create",
  params: {
    base_bdev_name: "aio0",
    name: "crypt0",
    key_name: "super_key"
  }
})

accel_conf = []
accel_conf.append(
  {
    method: "accel_crypto_key_create",
    params: {
      name: "super_key",
      cipher: encryption_key[:cipher],
      key: encryption_key[:key],
      key2: encryption_key[:key2]
    }
  }
)

spdk_config_json = {
    subsystems: [
      {
        subsystem: "accel",
        config: accel_conf
      },
      {
        subsystem: "bdev",
        config: bdev_conf
      }
    ]
}.to_json

puts(spdk_config_json)
