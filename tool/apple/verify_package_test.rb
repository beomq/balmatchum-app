require 'minitest/autorun'
require 'fileutils'
require_relative 'verify_package'

class ApplePackageTest < Minitest::Test
  def test_runner_declares_read_only_healthkit
    # Given / When: the production and debug Runner configuration files are read.
    %w[Info.plist Info-Debug-dev.plist].each do |name|
      info = ApplePackage.plist(File.expand_path("../../ios/Runner/#{name}", __dir__))
      # Then: both required purpose strings exist, with the verified capability gate.
      assert_kind_of String, info['NSHealthShareUsageDescription'], name
      refute_empty info['NSHealthShareUsageDescription'].strip, name
      assert_kind_of String, info['NSHealthUpdateUsageDescription'], name
      refute_empty info['NSHealthUpdateUsageDescription'].strip, name
      assert_equal true, info['BalmatchumHealthKitCapabilityVerified'], name
    end
    entitlements = ApplePackage.plist(File.expand_path('../../ios/Runner/Runner.entitlements', __dir__))
    assert_equal true, entitlements['com.apple.developer.healthkit']
  end

  def test_native_reader_requests_no_write_authorization
    # Given: the native HealthKit reader, not a purpose-string proxy.
    source = File.read(File.expand_path('../../ios/Runner/DailyStepsReader.swift', __dir__))
    # When: all HealthKit authorization share arguments are inspected.
    share_types = source.scan(/requestAuthorization\s*\(\s*toShare:\s*([^,]+),/)
    # Then: the reader requests reading, never a share/write type.
    refute_empty share_types
    assert share_types.all? { |argument| argument.first.strip == '[]' }
  end

  def test_package_accepts_read_only_healthkit_without_watch_healthkit
    # Given: a read-only iOS app and a companion without HealthKit entitlements.
    with_package do |app|
      # When / Then: the full package verification succeeds.
      assert ApplePackage.verify_app(app, 'com.beomq.balmatchum.dev', '1.0.8')
    end
  end

  def test_package_rejects_missing_blank_or_non_string_read_purpose
    [nil, '', '  ', false, 42].each do |invalid|
      # Given: an otherwise valid package with an invalid read purpose.
      with_package(info_changes: { 'NSHealthShareUsageDescription' => invalid }) do |app|
        # When: the package is verified.
        error = assert_raises(RuntimeError) do
          ApplePackage.verify_app(app, 'com.beomq.balmatchum.dev', '1.0.8')
        end
        # Then: the read-purpose contract rejects the package.
        assert_equal 'Missing HealthKit purpose: NSHealthShareUsageDescription', error.message
      end
    end
  end

  def test_package_rejects_missing_blank_or_non_string_update_purpose
    [nil, '', '  ', false, 42].each do |invalid|
      # Given: HealthKit is entitled but its required update purpose is invalid.
      with_package(info_changes: { 'NSHealthUpdateUsageDescription' => invalid }) do |app|
        # When: the package is verified.
        error = assert_raises(RuntimeError) do
          ApplePackage.verify_app(app, 'com.beomq.balmatchum.dev', '1.0.8')
        end
        # Then: the package fails locally instead of receiving ITMS-90683.
        assert_equal 'Missing HealthKit purpose: NSHealthUpdateUsageDescription', error.message
      end
    end
  end

  def test_package_rejects_unverified_healthkit_capability
    [nil, false, 'true'].each do |invalid|
      # Given: the capability gate is missing or not the boolean true.
      with_package(info_changes: { 'BalmatchumHealthKitCapabilityVerified' => invalid }) do |app|
        # When: the package is verified.
        error = assert_raises(RuntimeError) do
          ApplePackage.verify_app(app, 'com.beomq.balmatchum.dev', '1.0.8')
        end
        # Then: the unverified capability is rejected.
        assert_equal 'HealthKit capability not verified', error.message
      end
    end
  end

  def test_package_rejects_missing_healthkit_in_profile
    [nil, false, 'true'].each do |invalid|
      # Given: only the provisioning profile lacks a boolean HealthKit grant.
      with_package(profile_healthkit: invalid) do |app|
        # When: the package is verified.
        error = assert_raises(RuntimeError) do
          ApplePackage.verify_app(app, 'com.beomq.balmatchum.dev', '1.0.8')
        end
        # Then: the profile cannot authorize this package.
        assert_equal 'Missing HealthKit entitlement', error.message
      end
    end
  end

  def test_package_rejects_missing_healthkit_in_signature
    [nil, false, 'true'].each do |invalid|
      # Given: only the signed entitlements lack a boolean HealthKit grant.
      with_package(signed_healthkit: invalid) do |app|
        # When: the package is verified.
        error = assert_raises(RuntimeError) do
          ApplePackage.verify_app(app, 'com.beomq.balmatchum.dev', '1.0.8')
        end
        # Then: the signature cannot authorize this package.
        assert_equal 'Missing HealthKit entitlement', error.message
      end
    end
  end

  private

  def plist_xml(values)
    list = CFPropertyList::List.new
    list.value = CFPropertyList.guess(values)
    list.to_str(CFPropertyList::List::FORMAT_XML)
  end

  def with_package(info_changes: {}, profile_healthkit: true, signed_healthkit: true)
    Dir.mktmpdir('apple-package-test-') do |temp|
      app = File.join(temp, 'Runner.app')
      watch = File.join(app, 'Watch/BalmatchumWatch.app')
      FileUtils.mkdir_p(watch)
      info = { 'NSHealthShareUsageDescription' => 'read steps',
               'NSHealthUpdateUsageDescription' => 'no health data is written',
               'BalmatchumHealthKitCapabilityVerified' => true,
               'CFBundleIdentifier' => 'com.beomq.balmatchum.dev',
               'CFBundleShortVersionString' => '1.0.0', 'CFBundleVersion' => '1.0.8' }
      info_changes.each { |key, value| value.nil? ? info.delete(key) : info[key] = value }
      File.write(File.join(app, 'Info.plist'), plist_xml(info))
      File.write(File.join(watch, 'Info.plist'), plist_xml(
        'CFBundleIdentifier' => 'com.beomq.balmatchum.dev.watchkitapp',
        'WKCompanionAppBundleIdentifier' => 'com.beomq.balmatchum.dev',
        'CFBundleShortVersionString' => '1.0.0', 'CFBundleVersion' => '1.0.8'
      ))
      privacy = File.join(app, 'Frameworks/Flutter.framework/PrivacyInfo.xcprivacy')
      FileUtils.mkdir_p(File.dirname(privacy))
      File.write(privacy, plist_xml({}))
      real_command = ApplePackage.method(:command)
      signing_command = lambda do |*args|
        case args.first
        when 'security', 'codesign'
          next '' if args[1] == '--verify'
          bundle = args.last.include?('BalmatchumWatch.app') ? 'com.beomq.balmatchum.dev.watchkitapp' : 'com.beomq.balmatchum.dev'
          entitlements = { 'application-identifier' => "Q4E6NKD9VN.#{bundle}",
                           'com.apple.developer.team-identifier' => 'Q4E6NKD9VN',
                           'get-task-allow' => false }
          healthkit = args.first == 'security' ? profile_healthkit : signed_healthkit
          entitlements['com.apple.developer.healthkit'] = healthkit if bundle.end_with?('.dev') && !healthkit.nil?
          plist_xml(args.first == 'security' ? { 'Entitlements' => entitlements } : entitlements)
        else
          real_command.call(*args)
        end
      end
      ApplePackage.stub(:command, signing_command) { yield app }
    end
  end
end
