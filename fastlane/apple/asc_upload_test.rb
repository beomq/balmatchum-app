require 'minitest/autorun'
require_relative 'asc_preflight'

class AppleUploadRegistrationTest < Minitest::Test
  def build(number: '1.0.12', state: 'PROCESSING')
    { 'id' => 'registered-build', 'attributes' => { 'version' => number, 'processingState' => state } }
  end

  def verify(fetcher)
    ApplePreflight.verify_upload!(app_id: '6816329763', number: '1.0.12', fetcher: fetcher)
  end

  def test_accepts_exact_build_after_it_appears
    # Given: a fake ASC fetcher that initially sees no build, then the target build.
    requests = []
    pages = [[], [build]]
    fetcher = ->(path) { requests << path; pages.shift }
    # When: the bounded registration check runs without real waiting.
    result = ApplePreflight.stub(:sleep, ->(_) {}) { verify(fetcher) }
    # Then: it confirms the exact app and CFBundleVersion, not just transport success.
    assert_equal 'registered-build', result.fetch('id')
    assert_equal 2, requests.length
    assert requests.all? { |path| path == '/v1/builds?filter%5Bapp%5D=6816329763&filter%5Bversion%5D=1.0.12&limit=200' }
  end

  def test_accepts_valid_build
    # Given: ASC has completed processing.
    fetcher = ->(_) { [build(state: 'VALID')] }
    # When: registration is checked.
    result = verify(fetcher)
    # Then: the registered build is returned.
    assert_equal 'VALID', result.fetch('attributes').fetch('processingState')
  end

  def test_rejects_failed_invalid_or_unknown_state
    %w[FAILED INVALID UNKNOWN].each do |state|
      # Given: the target build is unusable or its state is unrecognized.
      fetcher = ->(_) { [build(state: state)] }
      # When: registration is checked.
      error = assert_raises(RuntimeError) { verify(fetcher) }
      # Then: the ASC state is reported rather than claiming delivery.
      assert_includes error.message, state
    end
  end

  def test_times_out_when_only_another_build_exists
    # Given: ASC never registers this CFBundleVersion.
    fetcher = ->(_) { [build(number: '1.0.11')] }
    timeout = lambda do |seconds, &operation|
      assert_operator seconds, :<=, 600
      operation.call
    end
    # When: the deadline expires at the first wait, without a real sleep.
    error = Timeout.stub(:timeout, timeout) do
      ApplePreflight.stub(:sleep, ->(_) { raise Timeout::Error }) do
        assert_raises(RuntimeError) { verify(fetcher) }
      end
    end
    # Then: absence is a delivery failure, including the requested build number.
    assert_includes error.message, '1.0.12'
    assert_includes error.message, 'not registered'
  end

  def test_api_failure_propagates_without_retrying_upload
    # Given: ASC cannot confirm registration.
    fetcher = ->(_) { raise 'ASC GET failed: HTTP 403' }
    # When: the check runs.
    error = assert_raises(RuntimeError) { verify(fetcher) }
    # Then: the authorization failure remains visible.
    assert_equal 'ASC GET failed: HTTP 403', error.message
  end
end
