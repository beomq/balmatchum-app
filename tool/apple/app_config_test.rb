require 'minitest/autorun'
require 'base64'
require 'tmpdir'
require_relative 'app_config'

class AppleAppConfigTest < Minitest::Test
  CONFIG = {
    'SERVER_URL' => 'https://balmatchum-prod.example.test/',
    'KAKAO_NATIVE_APP_KEY' => '0123456789abcdef0123456789abcdef',
    'GOOGLE_SERVER_CLIENT_ID' => '123456789012-server.apps.googleusercontent.com',
    'GOOGLE_CLIENT_ID' => '123456789012-ios.apps.googleusercontent.com',
    'APPLE_SIGN_IN_ENABLED' => 'true'
  }.freeze

  def generated_xcconfig(defines)
    encoded = defines.map { |key, value| Base64.strict_encode64("#{key}=#{value}") }.join(',')
    path = File.join(@temp, 'Generated.xcconfig')
    File.write(path, "FLUTTER_ROOT=/flutter\nDART_DEFINES=#{encoded}\nFLUTTER_BUILD_NUMBER=7\n")
    path
  end

  def setup
    @temp = Dir.mktmpdir('app-config-test-')
  end

  def teardown
    FileUtils.rm_rf(@temp)
  end

  def test_build_settings_derive_native_schemes_from_dart_values
    assert_equal(
      { 'KAKAO_URL_SCHEME' => 'kakao0123456789abcdef0123456789abcdef',
        'GOOGLE_REVERSED_CLIENT_ID' => 'com.googleusercontent.apps.123456789012-ios' },
      AppleAppConfig.build_settings(CONFIG)
    )
  end

  def test_dart_defines_must_contain_every_config_value
    AppleAppConfig.verify_dart_defines!(generated_xcconfig(CONFIG.merge('FLUTTER_APP_FLAVOR' => '')), CONFIG)
    error = assert_raises(RuntimeError) do
      AppleAppConfig.verify_dart_defines!(generated_xcconfig(CONFIG.merge('SERVER_URL' => '')), CONFIG)
    end
    assert_includes error.message, 'SERVER_URL'
  end

  def test_archived_plist_must_register_both_schemes_and_kakao_query
    settings = AppleAppConfig.build_settings(CONFIG)
    info = {
      'CFBundleURLTypes' => settings.values.map { |scheme| { 'CFBundleURLSchemes' => [scheme] } },
      'LSApplicationQueriesSchemes' => %w[kakaokompassauth kakaolink]
    }
    AppleAppConfig.verify_url_schemes!(info, settings)

    unconfigured = info.merge('CFBundleURLTypes' => [
      { 'CFBundleURLSchemes' => ['com.beomq.balmatchum.kakao-unconfigured'] },
      { 'CFBundleURLSchemes' => ['com.beomq.balmatchum.google-unconfigured'] }
    ])
    error = assert_raises(RuntimeError) { AppleAppConfig.verify_url_schemes!(unconfigured, settings) }
    assert_includes error.message, 'KAKAO_URL_SCHEME'

    error = assert_raises(RuntimeError) do
      AppleAppConfig.verify_url_schemes!(info.merge('LSApplicationQueriesSchemes' => []), settings)
    end
    assert_includes error.message, 'kakaokompassauth'
  end
end
