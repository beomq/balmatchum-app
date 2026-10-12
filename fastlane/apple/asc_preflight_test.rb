require 'minitest/autorun'
require_relative 'asc_preflight'

class ApplePreflightTest < Minitest::Test
  def verify(apps, groups)
    ApplePreflight.verify!(bundle: 'com.beomq.balmatchum.dev', app_id: '6816329763',
      fetcher: ->(path) { path.include?('betaGroups') ? groups : apps })
  end

  def app
    { 'id' => '6816329763', 'attributes' => { 'bundleId' => 'com.beomq.balmatchum.dev' } }
  end

  def test_accepts_exact_app_without_groups
    assert verify([app], [])
  end

  def test_selects_exact_bundle_when_api_returns_related_apps
    prod = { 'id' => '6816329577', 'attributes' => { 'bundleId' => 'com.beomq.balmatchum' } }
    assert ApplePreflight.verify!(bundle: 'com.beomq.balmatchum', app_id: '6816329577',
      fetcher: ->(path) { path.include?('betaGroups') ? [] : [app, prod] })
  end

  def test_rejects_missing_or_ambiguous_app
    assert_raises(RuntimeError) { verify([], []) }
    assert_raises(RuntimeError) { verify([app, app], []) }
  end

  def test_rejects_wrong_app_id
    assert_raises(RuntimeError) { verify([app.merge('id' => 'other')], []) }
  end

  def test_rejects_any_new_group_even_when_attribute_is_missing
    assert_raises(RuntimeError) { verify([app], [{ 'id' => 'new-group' }]) }
  end

  def group(attributes)
    { 'id' => 'group', 'attributes' => attributes }
  end

  def test_accepts_internal_group_with_automatic_distribution
    assert verify([app], [group('isInternalGroup' => true, 'hasAccessToAllBuilds' => true, 'publicLinkEnabled' => nil)])
  end

  def test_rejects_external_group
    assert_raises(RuntimeError) { verify([app], [group('isInternalGroup' => false)]) }
  end

  def test_rejects_internal_group_with_public_link
    assert_raises(RuntimeError) { verify([app], [group('isInternalGroup' => true, 'publicLinkEnabled' => true)]) }
  end

  def test_rejects_when_any_group_is_not_internal_only
    internal = group('isInternalGroup' => true)
    assert_raises(RuntimeError) { verify([app], [internal, group('isInternalGroup' => nil)]) }
  end
end
