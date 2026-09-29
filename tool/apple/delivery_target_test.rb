require 'minitest/autorun'
require_relative 'delivery_target'

class AppleDeliveryTargetTest < Minitest::Test
  def test_upload_contract
    { 'dev' => 'develop', 'prod' => 'main' }.each do |target, branch|
      AppleDeliveryTarget.verify!(target: target, mode: 'upload', ref: "refs/heads/#{branch}")
      %w[refs/heads/chore/cicd-validation refs/tags/main refs/heads/other].each do |ref|
        assert_raises(RuntimeError) { AppleDeliveryTarget.verify!(target: target, mode: 'upload', ref: ref) }
      end
    end
    assert_raises(RuntimeError) { AppleDeliveryTarget.verify!(target: 'dev', mode: 'upload', ref: 'refs/heads/main') }
    assert_raises(RuntimeError) { AppleDeliveryTarget.verify!(target: 'prod', mode: 'upload', ref: 'refs/heads/develop') }
  end

  def test_verify_allowlist
    AppleDeliveryTarget.verify!(target: 'dev', mode: 'verify', ref: 'refs/heads/chore/cicd-validation')
    assert_raises(RuntimeError) { AppleDeliveryTarget.verify!(target: 'dev', mode: 'verify', ref: 'refs/heads/other') }
  end
end
