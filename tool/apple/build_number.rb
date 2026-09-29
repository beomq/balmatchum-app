module AppleBuildNumber
  # Apple CFBundleVersion: first component <= 4 digits, others <= 2.
  def self.ordinal(value)
    raise 'Unsupported ASC build number' unless value.match?(/\A[1-9][0-9]{0,3}(?:\.[0-9]{1,2}){0,2}\z/)
    major, minor, patch = value.split('.').map(&:to_i)
    major * 10_000 + (minor || 0) * 100 + (patch || 0)
  end

  def self.next_after(versions)
    number = [10_000, *versions.map { |v| ordinal(v) + 1 }].max
    raise 'CFBundleVersion capacity exhausted' if number >= 100_000_000
    [number / 10_000, number / 100 % 100, number % 100].join('.')
  end
end
