# frozen_string_literal: true

require "test_helper"

class TypesTest < EavFieldTest
  def test_integer_casting_is_strict_and_preserves_bigint_boundaries
    assert_equal 42, EavField::Types.cast(:integer, "42")
    assert_equal(-7, EavField::Types.cast(:integer, "-7"))
    [ -(2**63), (2**63) - 1 ].each do |value|
      assert_equal value, EavField::Types.cast(:integer, value)
    end
    [ "abc", "1.2", 1.2, true, 2**63, -(2**63) - 1 ].each do |value|
      assert_raises(EavField::InvalidValue) { EavField::Types.cast(:integer, value) }
    end
  end

  def test_decimal_casting_rejects_loss_of_precision_and_nonfinite_numbers
    assert_equal BigDecimal("12.25"), EavField::Types.cast(:decimal, "12.25")
    assert_equal BigDecimal("0.0000000001"), EavField::Types.cast(:decimal, "0.0000000001")
    [ "abc", "NaN", "Infinity", "0.00000000001", "100000000000000000000" ].each do |value|
      assert_raises(EavField::InvalidValue) { EavField::Types.cast(:decimal, value) }
    end
  end

  def test_boolean_false_is_preserved_and_ambiguous_inputs_are_rejected
    [ false, "false", "0", 0 ].each do |value|
      assert_equal false, EavField::Types.cast(:boolean, value)
    end
    [ true, "true", "1", 1 ].each do |value|
      assert_equal true, EavField::Types.cast(:boolean, value)
    end
    [ "yes", "", 2, 1.0 ].each do |value|
      assert_raises(EavField::InvalidValue) { EavField::Types.cast(:boolean, value) }
    end
  end

  def test_dates_require_iso8601_and_validate_calendar_dates
    assert_equal Date.new(2024, 2, 29), EavField::Types.cast(:date, "2024-02-29")
    [ "2025-02-29", "29/02/2024", "2024-02-29extra" ].each do |value|
      assert_raises(EavField::InvalidValue) { EavField::Types.cast(:date, value) }
    end
  end

  def test_datetimes_normalize_offsets_to_utc
    assert_equal Time.utc(2026, 1, 2, 10, 30), EavField::Types.cast(:datetime, "2026-01-02T11:30:00+01:00")
    assert_equal Time.utc(2026, 1, 2, 10, 30), EavField::Types.cast(:datetime, DateTime.iso8601("2026-01-02T11:30:00+01:00"))
    zoned_time = ActiveSupport::TimeZone["UTC"].local(2026, 1, 2, 10, 30)
    assert_equal Time.utc(2026, 1, 2, 10, 30), EavField::Types.cast(:datetime, zoned_time)
    [ "tomorrow", "2026-01-02", "2026-01-02T10:30:00", "2026-02-30T10:30:00Z" ].each do |value|
      assert_raises(EavField::InvalidValue) { EavField::Types.cast(:datetime, value) }
    end
  end

  def test_json_normalizes_keys_and_rejects_non_json_objects
    assert_equal({ "tags" => [ "a", false, nil ] }, EavField::Types.cast(:json, { tags: [ "a", false, nil ] }))
    [ { bad: Object.new }, Float::NAN, { Object.new => "x" } ].each do |value|
      assert_raises(EavField::InvalidValue) { EavField::Types.cast(:json, value) }
    end
  end

  def test_strings_have_a_portable_length_limit_and_text_does_not
    assert_equal "a" * 255, EavField::Types.cast(:string, "a" * 255)
    assert_raises(EavField::InvalidValue) { EavField::Types.cast(:string, "a" * 256) }
    assert_raises(EavField::InvalidValue) { EavField::Types.cast(:string, 12) }
    assert_equal "a" * 1000, EavField::Types.cast(:text, "a" * 1000)
  end

  def test_optional_types_accept_nil_but_unknown_types_do_not
    EavField::Types::COLUMNS.each_key do |type|
      assert_nil EavField::Types.cast(type, nil)
    end
    assert_raises(EavField::InvalidValue) { EavField::Types.cast(:unknown, nil) }
  end
end
