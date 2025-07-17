defmodule Medpack.MedicinesTest do
  use Medpack.DataCase, async: true

  alias Medpack.Medicines

  describe "list_medicines/0" do
    test "returns all medicines ordered by most recent first" do
      now = DateTime.utc_now()
      earlier = DateTime.add(now, -60, :second)

      _medicine1 = insert(:medicine, name: "First Medicine", inserted_at: earlier)
      _medicine2 = insert(:medicine, name: "Second Medicine", inserted_at: now)

      medicines = Medicines.list_medicines()

      assert length(medicines) == 2
      # Most recent (Second Medicine) should be first
      assert hd(medicines).name == "Second Medicine"
      assert List.last(medicines).name == "First Medicine"
    end

    test "returns empty list when no medicines exist" do
      medicines = Medicines.list_medicines()

      assert medicines == []
    end
  end

  describe "get_medicine/1" do
    test "returns medicine when it exists" do
      medicine = insert(:medicine)

      result = Medicines.get_medicine(medicine.id)

      assert result.id == medicine.id
      assert result.name == medicine.name
    end

    test "returns nil when medicine does not exist" do
      result = Medicines.get_medicine(999)

      assert result == nil
    end
  end

  describe "get_medicine!/1" do
    test "returns medicine when it exists" do
      medicine = insert(:medicine)

      result = Medicines.get_medicine!(medicine.id)

      assert result.id == medicine.id
      assert result.name == medicine.name
    end

    test "raises Ecto.NoResultsError when medicine does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Medicines.get_medicine!(999)
      end
    end
  end

  describe "create_medicine/1" do
    test "creates medicine with valid attributes" do
      attrs = valid_medicine_attributes()

      assert {:ok, medicine} = Medicines.create_medicine(attrs)
      assert medicine.name == "Test Medicine"
      assert medicine.dosage_form == "tablet"
      assert medicine.status == "active"
    end

    test "returns error changeset with invalid attributes" do
      attrs = invalid_medicine_attributes()

      assert {:error, changeset} = Medicines.create_medicine(attrs)
      refute changeset.valid?
    end

    test "sets default values correctly" do
      attrs = valid_medicine_attributes()

      assert {:ok, medicine} = Medicines.create_medicine(attrs)
      assert medicine.status == "active"
      assert medicine.remaining_quantity == medicine.total_quantity
    end

    test "handles photo_paths as empty array by default" do
      attrs = valid_medicine_attributes()

      assert {:ok, medicine} = Medicines.create_medicine(attrs)
      assert medicine.photo_paths == []
    end

    test "accepts photo_paths when provided" do
      attrs =
        valid_medicine_attributes(%{
          photo_paths: ["/uploads/photo1.jpg", "/uploads/photo2.jpg"]
        })

      assert {:ok, medicine} = Medicines.create_medicine(attrs)
      assert medicine.photo_paths == ["/uploads/photo1.jpg", "/uploads/photo2.jpg"]
    end
  end

  describe "update_medicine/2" do
    test "updates medicine with valid attributes" do
      medicine = insert(:medicine, name: "Original Name")
      attrs = %{name: "Updated Name"}

      assert {:ok, updated_medicine} = Medicines.update_medicine(medicine, attrs)
      assert updated_medicine.name == "Updated Name"
    end

    test "returns error changeset with invalid attributes" do
      medicine = insert(:medicine)
      # Name is required
      attrs = %{name: nil}

      assert {:error, changeset} = Medicines.update_medicine(medicine, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "can update remaining quantity" do
      medicine =
        insert(:medicine,
          total_quantity: Decimal.new("30.0"),
          remaining_quantity: Decimal.new("30.0")
        )

      attrs = %{remaining_quantity: "15.0"}

      assert {:ok, updated_medicine} = Medicines.update_medicine(medicine, attrs)
      assert updated_medicine.remaining_quantity == Decimal.new("15.0")
    end

    test "validates remaining quantity does not exceed total" do
      medicine =
        insert(:medicine,
          total_quantity: Decimal.new("20.0"),
          remaining_quantity: Decimal.new("20.0")
        )

      attrs = %{remaining_quantity: "30.0"}

      assert {:error, changeset} = Medicines.update_medicine(medicine, attrs)
      refute changeset.valid?
      assert "cannot be greater than total quantity" in errors_on(changeset).remaining_quantity
    end
  end

  describe "delete_medicine/1" do
    test "deletes medicine successfully" do
      medicine = insert(:medicine)

      assert {:ok, deleted_medicine} = Medicines.delete_medicine(medicine)
      assert deleted_medicine.id == medicine.id
      assert Medicines.get_medicine(medicine.id) == nil
    end
  end

  describe "change_medicine/2" do
    test "returns changeset for medicine" do
      medicine = insert(:medicine)

      changeset = Medicines.change_medicine(medicine)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data == medicine
    end

    test "returns changeset with changes applied" do
      medicine = insert(:medicine, name: "Original")
      attrs = %{name: "Changed"}

      changeset = Medicines.change_medicine(medicine, attrs)

      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.name == "Changed"
    end
  end

  describe "list_expiring_medicines/0" do
    test "returns medicines expiring within 30 days" do
      today = Date.utc_today()

      # Medicine expiring in 15 days (should be included)
      _expiring_medicine =
        insert(:medicine,
          name: "Expiring Soon",
          expiration_date: Date.add(today, 15)
        )

      # Medicine expiring in 45 days (should not be included)
      insert(:medicine,
        name: "Not Expiring Soon",
        expiration_date: Date.add(today, 45)
      )

      # Already expired medicine (should not be included)
      insert(:medicine,
        name: "Already Expired",
        expiration_date: Date.add(today, -5)
      )

      expiring_medicines = Medicines.list_expiring_medicines()

      assert length(expiring_medicines) == 1
      assert hd(expiring_medicines).name == "Expiring Soon"
    end

    test "orders medicines by expiration date ascending" do
      today = Date.utc_today()

      _medicine1 =
        insert(:medicine,
          name: "Expires Later",
          expiration_date: Date.add(today, 25)
        )

      _medicine2 =
        insert(:medicine,
          name: "Expires Sooner",
          expiration_date: Date.add(today, 10)
        )

      expiring_medicines = Medicines.list_expiring_medicines()

      assert length(expiring_medicines) == 2
      assert hd(expiring_medicines).name == "Expires Sooner"
      assert List.last(expiring_medicines).name == "Expires Later"
    end

    test "includes medicines expiring today" do
      today = Date.utc_today()

      _medicine =
        insert(:medicine,
          name: "Expires Today",
          expiration_date: today
        )

      expiring_medicines = Medicines.list_expiring_medicines()

      assert length(expiring_medicines) == 1
      assert hd(expiring_medicines).name == "Expires Today"
    end

    test "returns empty list when no medicines are expiring soon" do
      today = Date.utc_today()

      # Medicine expiring in 45 days
      insert(:medicine, expiration_date: Date.add(today, 45))

      expiring_medicines = Medicines.list_expiring_medicines()

      assert expiring_medicines == []
    end
  end

  describe "list_expired_medicines/0" do
    test "returns medicines that have already expired" do
      today = Date.utc_today()

      # Expired medicine (should be included)
      _expired_medicine =
        insert(:medicine,
          name: "Already Expired",
          expiration_date: Date.add(today, -5)
        )

      # Current medicine (should not be included)
      insert(:medicine,
        name: "Still Good",
        expiration_date: Date.add(today, 10)
      )

      expired_medicines = Medicines.list_expired_medicines()

      assert length(expired_medicines) == 1
      assert hd(expired_medicines).name == "Already Expired"
    end

    test "does not include medicines expiring today" do
      today = Date.utc_today()

      insert(:medicine,
        name: "Expires Today",
        expiration_date: today
      )

      expired_medicines = Medicines.list_expired_medicines()

      assert expired_medicines == []
    end

    test "orders expired medicines by expiration date ascending" do
      today = Date.utc_today()

      _medicine1 =
        insert(:medicine,
          name: "Expired Long Ago",
          expiration_date: Date.add(today, -30)
        )

      _medicine2 =
        insert(:medicine,
          name: "Expired Recently",
          expiration_date: Date.add(today, -5)
        )

      expired_medicines = Medicines.list_expired_medicines()

      assert length(expired_medicines) == 2
      assert hd(expired_medicines).name == "Expired Long Ago"
      assert List.last(expired_medicines).name == "Expired Recently"
    end
  end

  describe "search_medicines/1" do
    test "finds medicines by name" do
      _medicine1 = insert(:medicine, name: "Ibuprofen 200mg")
      insert(:medicine, name: "Acetaminophen 500mg")

      results = Medicines.search_medicines("ibuprofen")

      assert length(results) == 1
      assert hd(results).name == "Ibuprofen 200mg"
    end

    test "finds medicines by brand name" do
      _medicine1 =
        insert(:medicine,
          name: "Generic Pain Relief",
          brand_name: "Advil"
        )

      insert(:medicine,
        name: "Other Medicine",
        brand_name: "Tylenol"
      )

      results = Medicines.search_medicines("advil")

      assert length(results) == 1
      assert hd(results).brand_name == "Advil"
    end

    test "finds medicines by generic name" do
      _medicine1 =
        insert(:medicine,
          name: "Brand Medicine",
          generic_name: "Ibuprofen"
        )

      insert(:medicine,
        name: "Other Medicine",
        generic_name: "Acetaminophen"
      )

      results = Medicines.search_medicines("ibuprofen")

      assert length(results) == 1
      assert hd(results).generic_name == "Ibuprofen"
    end

    test "finds medicines by active ingredient" do
      _medicine1 =
        insert(:medicine,
          name: "Test Medicine",
          active_ingredient: "Ibuprofen"
        )

      insert(:medicine,
        name: "Other Medicine",
        active_ingredient: "Acetaminophen"
      )

      results = Medicines.search_medicines("ibuprofen")

      assert length(results) == 1
      assert hd(results).active_ingredient == "Ibuprofen"
    end

    test "finds medicines by manufacturer" do
      _medicine1 =
        insert(:medicine,
          name: "Test Medicine",
          manufacturer: "Pfizer Inc"
        )

      insert(:medicine,
        name: "Other Medicine",
        manufacturer: "Johnson & Johnson"
      )

      results = Medicines.search_medicines("pfizer")

      assert length(results) == 1
      assert hd(results).manufacturer == "Pfizer Inc"
    end

    test "is case insensitive" do
      insert(:medicine, name: "IBUPROFEN")

      results = Medicines.search_medicines("ibuprofen")

      assert length(results) == 1
    end

    test "finds partial matches" do
      insert(:medicine, name: "Ibuprofen 200mg tablets")

      results = Medicines.search_medicines("200mg")

      assert length(results) == 1
    end

    test "returns multiple matches" do
      insert(:medicine, name: "Ibuprofen 200mg", brand_name: "Advil")
      insert(:medicine, name: "Ibuprofen 400mg", brand_name: "Motrin")

      results = Medicines.search_medicines("ibuprofen")

      assert length(results) == 2
    end

    test "returns empty list for no matches" do
      insert(:medicine, name: "Acetaminophen")

      results = Medicines.search_medicines("ibuprofen")

      assert results == []
    end

    test "handles nil search terms" do
      insert(:medicine, name: "Test Medicine")

      # search_medicines doesn't handle empty strings, only nil
      assert Medicines.search_medicines(nil) == []
    end

    test "handles empty search terms" do
      _medicine = insert(:medicine, name: "Test Medicine")

      # Empty string search should return medicines (current implementation behavior)
      results = Medicines.search_medicines("")
      assert length(results) == 1
      assert hd(results).name == "Test Medicine"
    end
  end

  describe "search_and_filter_medicines/1" do
    test "searches without filters" do
      _medicine1 = insert(:medicine, name: "Ibuprofen")
      insert(:medicine, name: "Acetaminophen")

      results = Medicines.search_and_filter_medicines(search: "ibuprofen")

      assert length(results) == 1
      assert hd(results).name == "Ibuprofen"
    end

    test "filters by dosage_form" do
      _medicine1 = insert(:medicine, dosage_form: "tablet")
      insert(:medicine, dosage_form: "syrup")

      results = Medicines.search_and_filter_medicines(filters: %{dosage_form: "tablet"})

      assert length(results) == 1
      assert hd(results).dosage_form == "tablet"
    end

    test "filters by container_type" do
      _medicine1 = insert(:medicine, container_type: "bottle")
      insert(:medicine, container_type: "box")

      results = Medicines.search_and_filter_medicines(filters: %{container_type: "bottle"})

      assert length(results) == 1
      assert hd(results).container_type == "bottle"
    end

    test "filters by status" do
      _medicine1 = insert(:medicine, status: "active")
      insert(:medicine, status: "expired")

      results = Medicines.search_and_filter_medicines(filters: %{status: "active"})

      assert length(results) == 1
      assert hd(results).status == "active"
    end

    test "filters by expiration_status: expired" do
      today = Date.utc_today()

      _expired_medicine =
        insert(:medicine,
          name: "Expired",
          expiration_date: Date.add(today, -5)
        )

      insert(:medicine,
        name: "Active",
        expiration_date: Date.add(today, 30)
      )

      results = Medicines.search_and_filter_medicines(filters: %{expiration_status: "expired"})

      assert length(results) == 1
      assert hd(results).name == "Expired"
    end

    test "filters by expiration_status: expiring_soon" do
      today = Date.utc_today()

      _expiring_medicine =
        insert(:medicine,
          name: "Expiring Soon",
          expiration_date: Date.add(today, 15)
        )

      insert(:medicine,
        name: "Good",
        expiration_date: Date.add(today, 60)
      )

      results =
        Medicines.search_and_filter_medicines(filters: %{expiration_status: "expiring_soon"})

      assert length(results) == 1
      assert hd(results).name == "Expiring Soon"
    end

    test "filters by expiration_status: good" do
      today = Date.utc_today()

      _good_medicine =
        insert(:medicine,
          name: "Good",
          expiration_date: Date.add(today, 60)
        )

      insert(:medicine,
        name: "Expiring Soon",
        expiration_date: Date.add(today, 15)
      )

      results = Medicines.search_and_filter_medicines(filters: %{expiration_status: "good"})

      assert length(results) == 1
      assert hd(results).name == "Good"
    end

    test "filters by expiration_status: unknown" do
      _unknown_medicine =
        insert(:medicine,
          name: "Unknown Expiration",
          expiration_date: nil
        )

      insert(:medicine,
        name: "Known Expiration",
        expiration_date: Date.add(Date.utc_today(), 30)
      )

      results = Medicines.search_and_filter_medicines(filters: %{expiration_status: "unknown"})

      assert length(results) == 1
      assert hd(results).name == "Unknown Expiration"
    end

    test "combines search and filters" do
      _medicine1 =
        insert(:medicine,
          name: "Ibuprofen Tablet",
          dosage_form: "tablet"
        )

      insert(:medicine,
        name: "Ibuprofen Syrup",
        dosage_form: "syrup"
      )

      insert(:medicine,
        name: "Acetaminophen Tablet",
        dosage_form: "tablet"
      )

      results =
        Medicines.search_and_filter_medicines(
          search: "ibuprofen",
          filters: %{dosage_form: "tablet"}
        )

      assert length(results) == 1
      assert hd(results).name == "Ibuprofen Tablet"
    end

    test "combines multiple filters" do
      _medicine1 =
        insert(:medicine,
          name: "Target Medicine",
          dosage_form: "tablet",
          container_type: "bottle",
          status: "active"
        )

      insert(:medicine,
        name: "Wrong Form",
        dosage_form: "syrup",
        container_type: "bottle",
        status: "active"
      )

      insert(:medicine,
        name: "Wrong Container",
        dosage_form: "tablet",
        container_type: "box",
        status: "active"
      )

      results =
        Medicines.search_and_filter_medicines(
          filters: %{
            dosage_form: "tablet",
            container_type: "bottle",
            status: "active"
          }
        )

      assert length(results) == 1
      assert hd(results).name == "Target Medicine"
    end

    test "ignores empty filter values" do
      _medicine1 = insert(:medicine, dosage_form: "tablet")
      _medicine2 = insert(:medicine, dosage_form: "syrup")

      results = Medicines.search_and_filter_medicines(filters: %{dosage_form: ""})

      assert length(results) == 2
    end

    test "ignores unknown filter keys" do
      _medicine1 = insert(:medicine, name: "Test Medicine")

      results = Medicines.search_and_filter_medicines(filters: %{unknown_key: "unknown_value"})

      assert length(results) == 1
      assert hd(results).name == "Test Medicine"
    end

    test "returns results ordered by most recent first" do
      now = DateTime.utc_now()
      earlier = DateTime.add(now, -60, :second)

      _medicine1 = insert(:medicine, name: "First Medicine", inserted_at: earlier)
      _medicine2 = insert(:medicine, name: "Second Medicine", inserted_at: now)

      results = Medicines.search_and_filter_medicines()

      assert length(results) == 2
      # Most recent (Second Medicine) should be first
      assert hd(results).name == "Second Medicine"
      assert List.last(results).name == "First Medicine"
    end
  end
end
