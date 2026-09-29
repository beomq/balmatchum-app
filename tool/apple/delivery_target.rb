module AppleDeliveryTarget
  def self.verify!(target:, mode:, ref:)
    raise 'Unknown delivery target or mode' unless %w[dev prod].include?(target) && %w[verify upload].include?(mode)
    if mode == 'upload'
      expected = target == 'dev' ? 'refs/heads/develop' : 'refs/heads/main'
      raise 'Upload target/ref mismatch' unless ref == expected
    else
      allowed = %w[refs/heads/develop refs/heads/main refs/heads/chore/cicd-validation]
      raise 'Unapproved verification ref' unless allowed.include?(ref)
    end
  end
end
