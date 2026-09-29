require 'open3'
require 'json'
require 'digest'
require 'tmpdir'
require 'cfpropertylist'

module ApplePackage
  def self.command(*args)
    out, _err, status = Open3.capture3(*args)
    raise "Package verification failed: #{args.first}" unless status.success?
    out
  end

  def self.plist(path)
    CFPropertyList.native_types(CFPropertyList::List.new(file: path).value)
  end

  def self.verify_app(app, bundle, number)
    ios = plist(File.join(app, 'Info.plist'))
    watch_path = File.join(app, 'Watch/BalmatchumWatch.app')
    watch = plist(File.join(watch_path, 'Info.plist'))
    raise 'Companion mismatch' unless watch['WKCompanionAppBundleIdentifier'] == bundle
    raise 'Marketing version mismatch' unless ios['CFBundleShortVersionString'] == watch['CFBundleShortVersionString']
    { app => bundle, watch_path => "#{bundle}.watchkitapp" }.each do |path, expected|
      info = plist(File.join(path, 'Info.plist'))
      raise 'Bundle/build mismatch' unless info['CFBundleIdentifier'] == expected && info['CFBundleVersion'] == number
      command('codesign', '--verify', '--deep', '--strict', path)
      Dir.mktmpdir('apple-profile-check-') do |temp|
        profile_path = File.join(temp, 'profile.plist')
        File.write(profile_path, command('security', 'cms', '-D', '-i', File.join(path, 'embedded.mobileprovision')))
        entitlements_path = File.join(temp, 'entitlements.plist')
        File.write(entitlements_path, command('codesign', '-d', '--entitlements', ':-', path))
        [plist(profile_path).fetch('Entitlements'), plist(entitlements_path)].each do |entitlements|
          raise 'Signing entitlement mismatch' unless entitlements['application-identifier'] == "Q4E6NKD9VN.#{expected}" && entitlements['com.apple.developer.team-identifier'] == 'Q4E6NKD9VN' && entitlements['get-task-allow'] == false
        end
      end
    end
    command('plutil', '-lint', File.join(app, 'Frameworks/Flutter.framework/PrivacyInfo.xcprivacy'))
  end

  def self.verify!(archive:, ipa:, bundle:, number:)
    verify_app(File.join(archive, 'Products/Applications/Runner.app'), bundle, number)
    Dir.mktmpdir('apple-ipa-check-') do |temp|
      command('ditto', '-x', '-k', ipa, temp)
      verify_app(File.join(temp, 'Payload/Runner.app'), bundle, number)
    end
    evidence = { bundle: bundle, build: number, sha: ENV['GITHUB_SHA'],
      ipa_sha256: Digest::SHA256.file(ipa).hexdigest, archive_and_ipa_verified: true }
    File.write(File.join(File.dirname(archive), 'identity-evidence.json'), JSON.pretty_generate(evidence))
    puts "APPLE_SIGNED_PACKAGE_VERIFIED bundle=#{bundle} build=#{number} ipa_sha256=#{evidence[:ipa_sha256]}"
  end
end
