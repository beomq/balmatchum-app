require 'fileutils'

module AppleDeliveryValidation
  def self.with_key(key_id:, key_path:)
    directory = File.join(Dir.home, '.appstoreconnect/private_keys')
    FileUtils.mkdir_p(directory, mode: 0700)
    path = File.join(directory, "AuthKey_#{key_id}.p8")
    # Never overwrite or remove a key owned by another process.
    File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0600) do |key|
      begin
        key.write(File.read(key_path))
        key.flush
        yield
      ensure
        File.delete(path)
      end
    end
  end
end
