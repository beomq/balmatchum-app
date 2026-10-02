module AppleDeliveryTarget
  def self.verify!(target:, mode:, ref:, event: nil, validation_upload: false)
    raise 'Unknown delivery target or mode' unless %w[dev prod].include?(target) && %w[verify upload].include?(mode)
    if mode == 'upload'
      expected = target == 'dev' ? 'refs/heads/develop' : 'refs/heads/main'
      manual_prod = target == 'prod' && ref == 'refs/heads/chore/cicd-validation' &&
        event == 'workflow_dispatch' && validation_upload
      raise 'Upload target/ref mismatch' unless ref == expected || manual_prod
    else
      allowed = %w[refs/heads/develop refs/heads/main refs/heads/chore/cicd-validation]
      raise 'Unapproved verification ref' unless allowed.include?(ref)
    end
  end
end
