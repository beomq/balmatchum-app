require 'json'
require 'base64'

# iOS build settings derived from the tool/release_app_config.sh JSON.
module AppleAppConfig
  KAKAO_QUERY_SCHEME = 'kakaokompassauth'.freeze

  def self.load(path)
    JSON.parse(File.read(path))
  end

  def self.build_settings(config)
    {
      'KAKAO_URL_SCHEME' => "kakao#{config.fetch('KAKAO_NATIVE_APP_KEY')}",
      # Same reversal AppDelegate uses to check the Google callback scheme.
      'GOOGLE_REVERSED_CLIENT_ID' => config.fetch('GOOGLE_CLIENT_ID').split('.').reverse.join('.')
    }
  end

  def self.verify_dart_defines!(generated_xcconfig, config)
    line = File.readlines(generated_xcconfig, chomp: true).find { |l| l.start_with?('DART_DEFINES=') }
    defines = line.to_s.delete_prefix('DART_DEFINES=').split(',').to_h do |encoded|
      key, value = Base64.strict_decode64(encoded).force_encoding('UTF-8').split('=', 2)
      [key, value.to_s]
    end
    config.each do |key, value|
      raise "Release dart define mismatch: #{key}" unless defines[key] == value
    end
  end

  def self.verify_url_schemes!(info, settings)
    schemes = Array(info['CFBundleURLTypes']).flat_map { |type| Array(type['CFBundleURLSchemes']) }
    settings.each do |name, scheme|
      raise "Release URL scheme missing: #{name}" unless schemes.include?(scheme)
    end
    return if Array(info['LSApplicationQueriesSchemes']).include?(KAKAO_QUERY_SCHEME)

    raise "Release query scheme missing: #{KAKAO_QUERY_SCHEME}"
  end
end
