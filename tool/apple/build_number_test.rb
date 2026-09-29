require 'minitest/autorun'
require_relative 'build_number'

class AppleBuildNumberTest < Minitest::Test
  def test_empty_and_unordered_history
    assert_equal '1.0.0', AppleBuildNumber.next_after([])
    assert_equal '3.2.10', AppleBuildNumber.next_after(%w[3.2.9 1 3.2.8])
  end

  def test_component_carry
    assert_equal '1.3.0', AppleBuildNumber.next_after(['1.2.99'])
    assert_equal '2.0.0', AppleBuildNumber.next_after(['1.99.99'])
  end

  def test_rejects_epoch_and_overflow
    assert_raises(RuntimeError) { AppleBuildNumber.next_after(['212345678']) }
    assert_raises(RuntimeError) { AppleBuildNumber.next_after(['9999.99.99']) }
  end
end
