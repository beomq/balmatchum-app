require 'minitest/autorun'
require 'tmpdir'
require 'rbconfig'
require 'socket'
require 'timeout'
require_relative 'delivery_validation'

class AppleDeliveryValidationTest < Minitest::Test
  def test_validation_streams_stdout_and_stderr_when_child_succeeds
    # Given: a real child that emits both output streams.
    command = [RbConfig.ruby, '-e', 'puts "STDOUT_TOKEN"; warn "STDERR_TOKEN"']
    # When: validation completes before its deadline.
    output, = capture_io do
      assert AppleDeliveryValidation.run!(command, timeout_seconds: 5)
    end
    # Then: neither output stream is hidden.
    assert_includes output, 'STDOUT_TOKEN'
    assert_includes output, 'STDERR_TOKEN'
  end

  def test_validation_propagates_apple_message_when_child_exits_nonzero
    # Given: a real child reporting an Apple rejection.
    command = [RbConfig.ruby, '-e', 'warn "ITMS-90683"; exit 23']
    error = nil
    # When: the command fails.
    output, = capture_io do
      error = assert_raises(RuntimeError) do
        AppleDeliveryValidation.run!(command, timeout_seconds: 5)
      end
    end
    # Then: the lane receives the exit status and Apple's visible message.
    assert_includes error.message, '23'
    assert_includes error.message, 'ITMS-90683'
    assert_includes output, 'ITMS-90683'
  end

  def test_validation_kills_and_reaps_hung_group_and_removes_key
    # Given: a bounded child that ignores TERM, with a readiness socket.
    Dir.mktmpdir('altool-hang-', '/tmp') do |home|
      socket_path = File.join(home, 'ready.sock')
      source = File.join(home, 'source.p8')
      File.write(source, 'fixture-key')
      key = File.join(home, '.appstoreconnect/private_keys/AuthKey_TEST.p8')
      child = 'require "socket"; trap("TERM", "IGNORE"); ' \
        'UNIXSocket.open(ARGV.fetch(0)) { |socket| socket.write("READY") }; sleep 1'
      real_timeout = Timeout.method(:timeout)
      real_kill = Process.method(:kill)
      signals = []
      timer_started = nil
      UNIXServer.open(socket_path) do |server|
        # Subscribe before launch; arm the short real deadline only after TERM
        # is ignored. No startup-speed assumption or sleep-for-readiness is used.
        deadline = lambda do |seconds, &operation|
          real_timeout.call(5) do
            peer = server.accept
            begin
              assert_equal 'READY', peer.read(5)
            ensure
              peer.close
            end
          end
          timer_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          real_timeout.call(seconds, &operation)
        end
        signal = lambda do |name, group|
          signals << [name, group]
          real_kill.call(name, group)
        end
        # When: the ready child exceeds a 50ms deadline and 50ms TERM grace.
        error = nil
        capture_io do
          Dir.stub(:home, home) do
            Timeout.stub(:timeout, deadline) do
              Process.stub(:kill, signal) do
                error = assert_raises(RuntimeError) do
                  AppleDeliveryValidation.with_key(key_id: 'TEST', key_path: source) do
                    AppleDeliveryValidation.run!([RbConfig.ruby, '-e', child, socket_path],
                      timeout_seconds: 0.05, grace_seconds: 0.05)
                  end
                end
              end
            end
          end
        end
        # Then: TERM escalates to KILL on the same group, the child is reaped,
        # and the private key is removed before the timeout reaches the lane.
        assert_includes error.message, 'timed out'
        assert_includes error.message, '0.05'
        assert_equal %w[TERM KILL], signals.map(&:first)
        group = signals.first.last
        assert_operator group, :<, 0
        assert_equal group, signals.last.last
        assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - timer_started, :<, 2
        assert_raises(Errno::ECHILD) { Process.waitpid(-group, Process::WNOHANG) }
        assert_raises(Errno::ESRCH) { real_kill.call(0, -group) }
        refute File.exist?(key)
      end
    end
  end

  def test_key_is_private_and_removed_after_validation
    # Given: an isolated altool home and a source API key.
    Dir.mktmpdir('altool-key-test-') do |home|
      source = File.join(home, 'source.p8')
      File.write(source, 'fixture-key')
      path = File.join(home, '.appstoreconnect/private_keys/AuthKey_TEST.p8')
      Dir.stub(:home, home) do
        # When: validation runs with its temporary key.
        result = AppleDeliveryValidation.with_key(key_id: 'TEST', key_path: source) do
          # Then: altool can read a private key only during the call.
          assert_equal 0600, File.stat(path).mode & 0777
          assert_equal File.read(source), File.read(path)
          :validated
        end
        assert_equal :validated, result
        refute File.exist?(path)
      end
    end
  end

  def test_key_is_removed_and_apple_error_propagates_when_validation_fails
    # Given: an isolated validation key.
    Dir.mktmpdir('altool-key-test-') do |home|
      source = File.join(home, 'source.p8')
      File.write(source, 'fixture-key')
      path = File.join(home, '.appstoreconnect/private_keys/AuthKey_TEST.p8')
      Dir.stub(:home, home) do
        # When: Apple's validation command fails.
        error = assert_raises(RuntimeError) do
          AppleDeliveryValidation.with_key(key_id: 'TEST', key_path: source) { raise 'ITMS-90683' }
        end
        # Then: the lane receives the original error and the key is removed.
        assert_equal 'ITMS-90683', error.message
        refute File.exist?(path)
      end
    end
  end

  def test_existing_key_is_preserved_when_destination_exists
    # Given: a key belonging to another process already exists.
    Dir.mktmpdir('altool-key-test-') do |home|
      directory = File.join(home, '.appstoreconnect/private_keys')
      FileUtils.mkdir_p(directory)
      path = File.join(directory, 'AuthKey_TEST.p8')
      File.write(path, 'existing-key')
      Dir.stub(:home, home) do
        # When: validation tries to claim the same path.
        assert_raises(Errno::EEXIST) do
          AppleDeliveryValidation.with_key(key_id: 'TEST', key_path: path) { flunk 'must not validate' }
        end
        # Then: no existing key is overwritten or removed.
        assert_equal 'existing-key', File.read(path)
      end
    end
  end
end
