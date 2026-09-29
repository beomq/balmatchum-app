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
end
