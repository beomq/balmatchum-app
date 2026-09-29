require 'net/http'
require 'json'
require 'jwt'
require 'openssl'

module ApplePreflight
  ORIGIN = 'https://api.appstoreconnect.apple.com'.freeze

  def self.get_pages(path, key_id:, issuer:, private_key:)
    rows = []
    seen = []
    url = URI.join(ORIGIN, path)
    while url
      raise 'Unexpected ASC pagination URL' unless url.scheme == 'https' && url.host == 'api.appstoreconnect.apple.com' && url.port == 443
      raise 'Repeated ASC page' if seen.include?(url.to_s)
      seen << url.to_s
      now = Time.now.to_i
      token = JWT.encode({ iss: issuer, iat: now, exp: now + 120,
        aud: 'appstoreconnect-v1', scope: ["GET #{url.request_uri}"] },
        private_key, 'ES256', { kid: key_id, typ: 'JWT' })
      request = Net::HTTP::Get.new(url)
      request['Authorization'] = "Bearer #{token}"
      response = Net::HTTP.start(url.host, url.port, use_ssl: true,
        open_timeout: 20, read_timeout: 60) { |http| http.request(request) }
      raise "ASC GET failed: HTTP #{response.code}" unless response.code == '200'
      body = JSON.parse(response.body)
      rows.concat(body.fetch('data'))
      next_url = body.fetch('links')['next']
      url = next_url ? URI.join(ORIGIN, next_url) : nil
    end
    rows
  end

  def self.verify!(bundle:, app_id:, fetcher:)
    apps = fetcher.call("/v1/apps?filter%5BbundleId%5D=#{bundle}&limit=200")
    apps = apps.select { |app| app.fetch('attributes')['bundleId'] == bundle }
    raise 'ASC target mismatch' unless apps.length == 1 && apps[0]['id'] == app_id && apps[0].fetch('attributes')['bundleId'] == bundle
    groups = fetcher.call("/v1/apps/#{app_id}/betaGroups?limit=200")
    # Fail closed if a group appears after the approved zero-group snapshot.
    # A server-side automatic-distribution toggle cannot be overridden by pilot.
    raise 'ASC beta groups changed: read-only review required before upload' unless groups.empty?
    true
  end
end
