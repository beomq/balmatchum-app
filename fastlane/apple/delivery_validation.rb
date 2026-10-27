require 'fileutils'
require 'open3'
require 'timeout'

module AppleDeliveryValidation
  def self.run!(command, timeout_seconds: 900, grace_seconds: 5)
    output = +''
    Open3.popen2e(*command, pgroup: true) do |input, stream, child|
      input.close
      completed = false
      begin
        status = Timeout.timeout(timeout_seconds) do
          stream.each_line do |line|
            output << line
            $stdout.write(line)
            $stdout.flush
          end
          child.value
        end
        completed = true
        raise "Apple validation failed (#{status}):\n#{output}" unless status.success?
        true
      rescue Timeout::Error
        raise "Apple validation timed out after #{timeout_seconds} seconds; terminating its process group.\n#{output}"
      ensure
        unless completed
          # Signal the group even if its leader exited but a descendant holds stdout.
          %w[TERM KILL].each do |signal|
            begin
              Process.kill(signal, -child.pid)
            rescue Errno::ESRCH
              break # The process group already exited between deadline and signal.
            end
            child.join(grace_seconds) if signal == 'TERM'
          end
          child.value # Reap before allowing the key-lifetime ensure to remove the key.
        end
      end
    end
  end

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
