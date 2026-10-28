require 'minitest/autorun'
require 'json'
require 'yaml'
require_relative 'delivery_target'

class AppleDeliveryTargetTest < Minitest::Test
  def test_upload_contract
    { 'dev' => 'develop', 'prod' => 'main' }.each do |target, branch|
      AppleDeliveryTarget.verify!(target: target, mode: 'upload', ref: "refs/heads/#{branch}")
      %w[refs/heads/chore/cicd-validation refs/tags/main refs/heads/other].each do |ref|
        assert_raises(RuntimeError) { AppleDeliveryTarget.verify!(target: target, mode: 'upload', ref: ref) }
      end
    end
    assert_raises(RuntimeError) { AppleDeliveryTarget.verify!(target: 'dev', mode: 'upload', ref: 'refs/heads/main') }
    assert_raises(RuntimeError) { AppleDeliveryTarget.verify!(target: 'prod', mode: 'upload', ref: 'refs/heads/develop') }
  end

  def test_verify_allowlist
    AppleDeliveryTarget.verify!(target: 'dev', mode: 'verify', ref: 'refs/heads/chore/cicd-validation')
    assert_raises(RuntimeError) { AppleDeliveryTarget.verify!(target: 'dev', mode: 'verify', ref: 'refs/heads/other') }
  end

  def test_manual_dev_on_develop_uploads
    assert_equal [['dev', 'upload']],
      workflow_deliveries(event: 'workflow_dispatch', ref: 'refs/heads/develop', input: 'dev')
  end

  def test_manual_prod_stays_verify
    %w[refs/heads/develop refs/heads/main].each do |ref|
      assert_equal [['prod', 'verify']],
        workflow_deliveries(event: 'workflow_dispatch', ref: ref, input: 'prod')
    end
  end

  def test_manual_dev_on_other_refs_cannot_upload
    %w[refs/heads/main refs/heads/chore/cicd-validation refs/heads/other refs/tags/develop].each do |ref|
      deliveries = workflow_deliveries(event: 'workflow_dispatch', ref: ref, input: 'dev')
      assert_equal ['verify'], deliveries.map(&:last).uniq
    end
  end

  def test_main_push_still_uploads_prod_under_activation_gate
    assert_equal [['prod', 'upload']],
      workflow_deliveries(event: 'push', ref: 'refs/heads/main', input: '', enabled: 'true')
    assert_equal [['prod', 'verify']],
      workflow_deliveries(event: 'push', ref: 'refs/heads/main', input: '', enabled: 'false')
  end

  def test_workflow_mode_and_target_matrix
    refs = %w[refs/heads/develop refs/heads/main refs/heads/chore/cicd-validation
              refs/heads/other refs/tags/develop refs/tags/main
              refs/tags/chore/cicd-validation refs/tags/other]
    cases = 0
    %w[push workflow_dispatch].product(refs, %w[dev prod], ['true', 'false', '']).each do |event, ref, input, enabled|
      ref_name = ref.sub(%r{\Arefs/(heads|tags)/}, '')
      targets = if ref_name == 'chore/cicd-validation'
        %w[dev prod]
      elsif event == 'workflow_dispatch'
        [input]
      else
        [ref_name == 'main' ? 'prod' : 'dev']
      end
      upload = enabled == 'true' &&
        ((event == 'push' && ref_name != 'chore/cicd-validation') ||
         (event == 'workflow_dispatch' && input == 'dev' && ref == 'refs/heads/develop'))
      expected = targets.map { |target| [target, upload ? 'upload' : 'verify'] }
      actual = workflow_deliveries(event: event, ref: ref, input: input, enabled: enabled)
      assert_equal expected, actual, [event, ref, input, enabled].inspect
      actual.each do |target, mode|
        cases += 1
        allowed = if mode == 'upload'
          ref == (target == 'dev' ? 'refs/heads/develop' : 'refs/heads/main')
        else
          %w[refs/heads/develop refs/heads/main refs/heads/chore/cicd-validation].include?(ref)
        end
        if allowed
          assert_nil AppleDeliveryTarget.verify!(target: target, mode: mode, ref: ref)
        else
          assert_raises(RuntimeError) { AppleDeliveryTarget.verify!(target: target, mode: mode, ref: ref) }
        end
      end
    end
    assert_equal 120, cases
  end

  private

  def workflow_deliveries(event:, ref:, input:, enabled: 'true')
    workflow = YAML.load_file(File.expand_path('../../.github/workflows/apple-upload.yml', __dir__))
    job = workflow.fetch('jobs').fetch('signed-build')
    github = { event_name: event, ref: ref, ref_name: ref.sub(%r{\Arefs/(heads|tags)/}, '') }
    inputs = { target: input }
    vars = { APPLE_UPLOAD_ENABLED: enabled }
    matrix = {}
    # Evaluate the workflow's actual equality/boolean/fromJSON expressions,
    # rather than a separate copy of the delivery policy.
    evaluate = lambda do |expression|
      source = expression.delete_prefix('${{').delete_suffix('}}')
        .gsub(/\b(github|inputs|vars|matrix)\.(\w+)/, '\1.fetch(:\2)')
        .gsub('fromJSON(', 'JSON.parse(')
      eval(source, binding)
    end
    evaluate.call(job.fetch('strategy').fetch('matrix').fetch('target')).map do |target|
      matrix = { target: target }
      env = job.fetch('env')
      [evaluate.call(env.fetch('DELIVERY_TARGET')), evaluate.call(env.fetch('DELIVERY_MODE'))]
    end
  end
end
