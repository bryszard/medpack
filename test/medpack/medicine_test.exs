defmodule Medpack.MedicineTest do
  use Medpack.DataCase, async: true

  alias Medpack.Medicine

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = valid_medicine_attributes()

      changeset = Medicine.changeset(%Medicine{}, attrs)

      assert changeset.valid?
      assert changeset.changes.name == "Test Medicine"
      assert changeset.changes.dosage_form == "tablet"
      assert changeset.changes.strength_value == Decimal.new("10.0")
    end

    test "requires name field" do
      attrs = valid_medicine_attributes(%{name: nil})

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires dosage_form field" do
      attrs = valid_medicine_attributes(%{dosage_form: nil})

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).dosage_form
    end

    test "validates dosage_form inclusion" do
      valid_forms = [
        "tablet",
        "capsule",
        "syrup",
        "suspension",
        "solution",
        "cream",
        "ointment",
        "gel",
        "lotion",
        "drops",
        "injection",
        "inhaler",
        "spray",
        "patch",
        "suppository"
      ]

      for form <- valid_forms do
        attrs = valid_medicine_attributes(%{dosage_form: form})
        changeset = Medicine.changeset(%Medicine{}, attrs)
        assert changeset.valid?, "#{form} should be valid"
      end

      # Test invalid form
      attrs = valid_medicine_attributes(%{dosage_form: "invalid_form"})
      changeset = Medicine.changeset(%Medicine{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).dosage_form
    end

    test "requires strength_value field" do
      attrs = valid_medicine_attributes(%{strength_value: nil})

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).strength_value
    end

    test "validates strength_value is greater than 0" do
      attrs = valid_medicine_attributes(%{strength_value: "0"})

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).strength_value
    end

    test "validates strength_value negative number" do
      attrs = valid_medicine_attributes(%{strength_value: "-5.0"})

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).strength_value
    end

    test "requires strength_unit field" do
      attrs = valid_medicine_attributes(%{strength_unit: nil})

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).strength_unit
    end

    test "requires container_type field" do
      attrs = valid_medicine_attributes(%{container_type: nil})

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).container_type
    end

    test "validates container_type inclusion" do
      valid_types = [
        "bottle",
        "box",
        "tube",
        "vial",
        "inhaler",
        "blister_pack",
        "sachet",
        "ampoule"
      ]

      for type <- valid_types do
        attrs = valid_medicine_attributes(%{container_type: type})
        changeset = Medicine.changeset(%Medicine{}, attrs)
        assert changeset.valid?, "#{type} should be valid"
      end

      # Test invalid type
      attrs = valid_medicine_attributes(%{container_type: "invalid_type"})
      changeset = Medicine.changeset(%Medicine{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).container_type
    end

    test "requires total_quantity field" do
      attrs = valid_medicine_attributes(%{total_quantity: nil})

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).total_quantity
    end

    test "validates total_quantity is greater than 0" do
      attrs = valid_medicine_attributes(%{total_quantity: "0"})

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).total_quantity
    end

    test "requires quantity_unit field" do
      attrs = valid_medicine_attributes(%{quantity_unit: nil})

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).quantity_unit
    end

    test "validates status inclusion" do
      valid_statuses = ["active", "expired", "empty", "recalled"]

      for status <- valid_statuses do
        attrs = valid_medicine_attributes(%{status: status})
        changeset = Medicine.changeset(%Medicine{}, attrs)
        assert changeset.valid?, "#{status} should be valid"
      end

      # Test invalid status
      attrs = valid_medicine_attributes(%{status: "invalid_status"})
      changeset = Medicine.changeset(%Medicine{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "validates remaining_quantity is not negative" do
      attrs = valid_medicine_attributes(%{remaining_quantity: "-5.0"})

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).remaining_quantity
    end

    test "validates remaining_quantity does not exceed total_quantity" do
      attrs =
        valid_medicine_attributes(%{
          total_quantity: "20.0",
          remaining_quantity: "30.0"
        })

      changeset = Medicine.changeset(%Medicine{}, attrs)

      refute changeset.valid?
      assert "cannot be greater than total quantity" in errors_on(changeset).remaining_quantity
    end

    test "allows remaining_quantity equal to total_quantity" do
      attrs =
        valid_medicine_attributes(%{
          total_quantity: "30.0",
          remaining_quantity: "30.0"
        })

      changeset = Medicine.changeset(%Medicine{}, attrs)

      assert changeset.valid?
    end

    test "allows remaining_quantity less than total_quantity" do
      attrs =
        valid_medicine_attributes(%{
          total_quantity: "30.0",
          remaining_quantity: "15.0"
        })

      changeset = Medicine.changeset(%Medicine{}, attrs)

      assert changeset.valid?
    end

    test "sets default remaining_quantity to total_quantity when not provided" do
      attrs = valid_medicine_attributes(%{total_quantity: "50.0"})
      attrs = Map.delete(attrs, :remaining_quantity)

      changeset = Medicine.changeset(%Medicine{}, attrs)

      assert changeset.valid?
      assert get_field(changeset, :remaining_quantity) == Decimal.new("50.0")
    end

    test "preserves explicit remaining_quantity when provided" do
      attrs =
        valid_medicine_attributes(%{
          total_quantity: "50.0",
          remaining_quantity: "25.0"
        })

      changeset = Medicine.changeset(%Medicine{}, attrs)

      assert changeset.valid?
      assert get_field(changeset, :remaining_quantity) == Decimal.new("25.0")
    end

    test "accepts optional fields" do
      attrs =
        valid_medicine_attributes(%{
          brand_name: "Brand Name",
          generic_name: "Generic Name",
          active_ingredient: "Active Ingredient",
          lot_number: "LOT123",
          strength_denominator_value: "5.0",
          strength_denominator_unit: "ml",
          expiration_date: ~D[2025-12-31],
          manufacturer: "Test Manufacturer",
          photo_paths: ["/uploads/photo1.jpg", "/uploads/photo2.jpg"]
        })

      changeset = Medicine.changeset(%Medicine{}, attrs)

      assert changeset.valid?
      assert changeset.changes.brand_name == "Brand Name"
      assert changeset.changes.expiration_date == ~D[2025-12-31]
      assert changeset.changes.photo_paths == ["/uploads/photo1.jpg", "/uploads/photo2.jpg"]
    end

    test "handles decimal string conversions correctly" do
      attrs =
        valid_medicine_attributes(%{
          strength_value: "12.5",
          total_quantity: "100.0",
          remaining_quantity: "75.5",
          strength_denominator_value: "5.0"
        })

      changeset = Medicine.changeset(%Medicine{}, attrs)

      assert changeset.valid?
      assert changeset.changes.strength_value == Decimal.new("12.5")
      assert changeset.changes.total_quantity == Decimal.new("100.0")
      assert changeset.changes.remaining_quantity == Decimal.new("75.5")
      assert changeset.changes.strength_denominator_value == Decimal.new("5.0")
    end
  end

  describe "create_changeset/1" do
    test "creates changeset for new medicine" do
      attrs = valid_medicine_attributes()

      changeset = Medicine.create_changeset(attrs)

      assert changeset.valid?
      assert changeset.data == %Medicine{}
    end

    test "works without attributes" do
      changeset = Medicine.create_changeset()

      refute changeset.valid?
      assert changeset.data == %Medicine{}
    end
  end

  describe "strength_display/1" do
    test "displays strength with unit" do
      medicine =
        build(:medicine,
          strength_value: Decimal.new("500.0"),
          strength_unit: "mg"
        )

      result = Medicine.strength_display(medicine)

      assert result == "500.0mg"
    end

    test "displays strength with denominator" do
      medicine =
        build(:medicine,
          strength_value: Decimal.new("5.0"),
          strength_unit: "mg",
          strength_denominator_value: Decimal.new("1.0"),
          strength_denominator_unit: "ml"
        )

      result = Medicine.strength_display(medicine)

      assert result == "5.0mg/1.0ml"
    end

    test "handles nil denominator values" do
      medicine =
        build(:medicine,
          strength_value: Decimal.new("250.0"),
          strength_unit: "mg",
          strength_denominator_value: nil,
          strength_denominator_unit: nil
        )

      result = Medicine.strength_display(medicine)

      assert result == "250.0mg"
    end
  end

  describe "quantity_display/1" do
    test "displays remaining/total quantity with unit" do
      medicine =
        build(:medicine,
          remaining_quantity: Decimal.new("15.0"),
          total_quantity: Decimal.new("30.0"),
          quantity_unit: "tablets"
        )

      result = Medicine.quantity_display(medicine)

      assert result == "15.0/30.0 tablets"
    end

    test "handles zero remaining quantity" do
      medicine =
        build(:medicine,
          remaining_quantity: Decimal.new("0.0"),
          total_quantity: Decimal.new("50.0"),
          quantity_unit: "ml"
        )

      result = Medicine.quantity_display(medicine)

      assert result == "0.0/50.0 ml"
    end
  end

  describe "usage_percentage/1" do
    test "calculates correct percentage for partial usage" do
      medicine =
        build(:medicine,
          remaining_quantity: Decimal.new("15.0"),
          total_quantity: Decimal.new("30.0")
        )

      result = Medicine.usage_percentage(medicine)

      assert result == 50.0
    end

    test "calculates 100% for full container" do
      medicine =
        build(:medicine,
          remaining_quantity: Decimal.new("30.0"),
          total_quantity: Decimal.new("30.0")
        )

      result = Medicine.usage_percentage(medicine)

      assert result == 100.0
    end

    test "calculates 0% for empty container" do
      medicine =
        build(:medicine,
          remaining_quantity: Decimal.new("0.0"),
          total_quantity: Decimal.new("30.0")
        )

      result = Medicine.usage_percentage(medicine)

      assert result == 0.0
    end

    test "handles zero total quantity" do
      medicine =
        build(:medicine,
          remaining_quantity: Decimal.new("0.0"),
          total_quantity: Decimal.new("0.0")
        )

      result = Medicine.usage_percentage(medicine)

      assert result == 0.0
    end

    test "rounds to one decimal place" do
      medicine =
        build(:medicine,
          remaining_quantity: Decimal.new("10.0"),
          total_quantity: Decimal.new("30.0")
        )

      result = Medicine.usage_percentage(medicine)

      assert result == 33.3
    end
  end

  describe "search_matches/2" do
    test "finds matches in name field" do
      medicine = build(:medicine, name: "Ibuprofen 200mg")

      matches = Medicine.search_matches(medicine, "ibuprofen")

      assert matches == [{:name, "Ibuprofen 200mg"}]
    end

    test "finds matches in brand_name field" do
      medicine =
        build(:medicine,
          name: "Generic Medicine",
          brand_name: "Advil"
        )

      matches = Medicine.search_matches(medicine, "advil")

      assert matches == [{:brand_name, "Advil"}]
    end

    test "finds matches in generic_name field" do
      medicine =
        build(:medicine,
          name: "Brand Medicine",
          generic_name: "Acetaminophen"
        )

      matches = Medicine.search_matches(medicine, "acetaminophen")

      assert matches == [{:generic_name, "Acetaminophen"}]
    end

    test "finds matches in active_ingredient field" do
      medicine =
        build(:medicine,
          name: "Test Medicine",
          active_ingredient: "Ibuprofen"
        )

      matches = Medicine.search_matches(medicine, "ibuprofen")

      assert matches == [{:active_ingredient, "Ibuprofen"}]
    end

    test "finds matches in manufacturer field" do
      medicine =
        build(:medicine,
          name: "Test Medicine",
          manufacturer: "Pfizer Inc"
        )

      matches = Medicine.search_matches(medicine, "pfizer")

      assert matches == [{:manufacturer, "Pfizer Inc"}]
    end

    test "finds multiple matches across fields" do
      medicine =
        build(:medicine,
          name: "Ibuprofen Advanced",
          brand_name: "Advil",
          active_ingredient: "Ibuprofen"
        )

      matches = Medicine.search_matches(medicine, "ibuprofen")

      # Should find matches in both name and active_ingredient
      assert length(matches) == 2
      assert {:name, "Ibuprofen Advanced"} in matches
      assert {:active_ingredient, "Ibuprofen"} in matches
    end

    test "returns empty list for no matches" do
      medicine = build(:medicine, name: "Acetaminophen")

      matches = Medicine.search_matches(medicine, "ibuprofen")

      assert matches == []
    end

    test "returns empty list for empty search query" do
      medicine = build(:medicine, name: "Test Medicine")

      matches = Medicine.search_matches(medicine, "")

      assert matches == []
    end

    test "returns empty list for nil search query" do
      medicine = build(:medicine, name: "Test Medicine")

      matches = Medicine.search_matches(medicine, nil)

      assert matches == []
    end

    test "is case insensitive" do
      medicine = build(:medicine, name: "IBUPROFEN")

      matches = Medicine.search_matches(medicine, "ibuprofen")

      assert matches == [{:name, "IBUPROFEN"}]
    end

    test "handles nil field values gracefully" do
      medicine =
        build(:medicine,
          name: "Test Medicine",
          brand_name: nil,
          generic_name: nil,
          active_ingredient: nil,
          manufacturer: nil
        )

      matches = Medicine.search_matches(medicine, "test")

      assert matches == [{:name, "Test Medicine"}]
    end
  end
end
