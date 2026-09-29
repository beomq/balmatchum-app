require 'tmpdir'
require 'securerandom'
require 'open3'
require 'bundler'
require 'fastlane'
require 'shellwords'

File.umask(0o077)
Dir.mktmpdir('apple-delivery-') do |temp|
  keychain = File.join(temp, 'signing.keychain-db')
  keychain_password = SecureRandom.hex(32)
  search_list, _, search_status = Open3.capture3('security', 'list-keychains', '-d', 'user')
  raise 'Cannot read keychain search list' unless search_status.success?
  original_keychains = Shellwords.split(search_list)
  begin
    ENV['MATCH_KEYCHAIN_NAME'] = keychain
    ENV['MATCH_KEYCHAIN_PASSWORD'] = keychain_password
    ENV['ASC_KEY_PATH'] = File.join(temp, "AuthKey_#{ENV.fetch('ASC_KEY_ID')}.p8")
    File.write(ENV['ASC_KEY_PATH'], ENV.delete('ASC_PRIVATE_KEY'))
    ssh = File.join(temp, 'match-key')
    File.write(ssh, ENV.fetch('MATCH_GIT_PRIVATE_KEY').rstrip + "\n")
    _, _, status = Open3.capture3('ssh-keygen', '-y', '-f', ssh)
    raise 'CI SSH key format is invalid' unless status.success?
    ENV['MATCH_GIT_PRIVATE_KEY'] = ssh
    ENV['APPLE_OUTPUT_DIR'] = File.join(ENV.fetch('RUNNER_TEMP'), 'apple-output')
    # security accepts the generated ephemeral keychain password as an argument;
    # source P12/match/ASC credentials never appear in argv.
    _, _, status = Open3.capture3('security', 'create-keychain', '-p', keychain_password, keychain)
    raise 'Temporary keychain creation failed' unless status.success?
    _, _, status = Open3.capture3('security', 'unlock-keychain', '-p', keychain_password, keychain)
    raise 'Temporary keychain unlock failed' unless status.success?
    _, _, status = Open3.capture3('security', 'set-keychain-settings', '-lut', '21600', keychain)
    raise 'Temporary keychain settings failed' unless status.success?
    _, _, status = Open3.capture3('security', 'list-keychains', '-d', 'user', '-s', keychain, *original_keychains)
    raise 'Temporary keychain search registration failed' unless status.success?
    fastfile = File.expand_path('../../fastlane/apple/Fastfile', __dir__)
    Fastlane.load_actions
    Fastlane::LaneManager.cruise_lane('ios', 'upload_only',
      { target: ENV.fetch('DELIVERY_TARGET'), mode: ENV.fetch('DELIVERY_MODE') }, fastfile)
  ensure
    Open3.capture3('security', 'list-keychains', '-d', 'user', '-s', *original_keychains)
    Open3.capture3('security', 'delete-keychain', keychain) if File.exist?(keychain)
  end
end
