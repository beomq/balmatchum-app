require 'minitest/autorun'
require 'tmpdir'
require_relative 'delivery_validation'

class AppleDeliveryValidationTest < Minitest::Test
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
