require 'minitest/autorun'
require_relative 'verify_package'

class ApplePackageTest < Minitest::Test
  def test_runner_declares_both_healthkit_purposes
    info = ApplePackage.plist(File.expand_path('../../ios/Runner/Info.plist', __dir__))
    %w[NSHealthShareUsageDescription NSHealthUpdateUsageDescription].each do |key|
      assert_kind_of String, info[key], key
      refute_empty info[key].strip, key
    end
  end

  def test_package_rejects_missing_or_blank_health_purpose_before_signing
    %w[NSHealthShareUsageDescription NSHealthUpdateUsageDescription].each do |key|
      [nil, '', '  '].each do |invalid|
        info = { 'NSHealthShareUsageDescription' => 'read steps',
                 'NSHealthUpdateUsageDescription' => 'no writes', key => invalid }
        ApplePackage.stub(:plist, info) do
          error = assert_raises(RuntimeError) do
            ApplePackage.verify_app('Runner.app', 'com.beomq.balmatchum.dev', '1.0.8')
          end
          assert_equal "Missing HealthKit purpose: #{key}", error.message
        end
      end
    end
  end
end
