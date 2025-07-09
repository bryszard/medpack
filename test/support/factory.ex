defmodule Medpack.Factory do
  @moduledoc """
  Test data factories for Medpack application using ExMachina.
  """

  use ExMachina.Ecto, repo: Medpack.Repo

  alias Medpack.Medicine
  alias Medpack.BatchProcessing.{Entry, EntryImage}

  # Medicine Factories

  def medicine_factory do
    %Medicine{
      name: sequence(:name, &"Test Medicine #{&1}"),
      brand_name: sequence(:brand_name, &"Brand #{&1}"),
      generic_name: sequence(:generic_name, &"Generic #{&1}"),
      dosage_form: sequence(:dosage_form, ["tablet", "capsule", "syrup", "cream"]),
      active_ingredient: sequence(:active_ingredient, &"Active Ingredient #{&1}"),
      strength_value: Decimal.new("10.0"),
      strength_unit: "mg",
      container_type: sequence(:container_type, ["bottle", "box", "tube"]),
      total_quantity: Decimal.new("30.0"),
      remaining_quantity: Decimal.new("30.0"),
      quantity_unit: "tablets",
      status: "active",
      expiration_date: Date.add(Date.utc_today(), 365),
      manufacturer: sequence(:manufacturer, &"Manufacturer #{&1}"),
      indication: "For testing purposes",
      notes: "Test medicine notes"
    }
  end

  def expired_medicine_factory do
    medicine_factory()
    |> Map.put(:expiration_date, Date.add(Date.utc_today(), -30))
    |> Map.put(:status, "expired")
  end

  def expiring_soon_medicine_factory do
    medicine_factory()
    |> Map.put(:expiration_date, Date.add(Date.utc_today(), 15))
  end

  def tablet_medicine_factory do
    medicine_factory()
    |> Map.put(:dosage_form, "tablet")
    |> Map.put(:container_type, "bottle")
    |> Map.put(:quantity_unit, "tablets")
  end

  def liquid_medicine_factory do
    medicine_factory()
    |> Map.put(:dosage_form, "syrup")
    |> Map.put(:container_type, "bottle")
    |> Map.put(:quantity_unit, "ml")
    |> Map.put(:total_quantity, Decimal.new("250.0"))
    |> Map.put(:remaining_quantity, Decimal.new("200.0"))
  end

  def partially_used_medicine_factory do
    medicine_factory()
    |> Map.put(:remaining_quantity, Decimal.new("15.0"))
  end

  def empty_medicine_factory do
    medicine_factory()
    |> Map.put(:remaining_quantity, Decimal.new("0.0"))
    |> Map.put(:status, "empty")
  end

  # Batch Processing Factories

  def batch_entry_factory do
    %Entry{
      batch_id: sequence(:batch_id, &"batch_#{&1}"),
      entry_number: sequence(:entry_number, & &1),
      status: :pending,
      ai_analysis_status: :pending,
      approval_status: :pending
    }
  end

  def processing_batch_entry_factory do
    batch_entry_factory()
    |> Map.put(:ai_analysis_status, :processing)
  end

  def analyzed_batch_entry_factory do
    batch_entry_factory()
    |> Map.put(:ai_analysis_status, :complete)
    |> Map.put(:analyzed_at, DateTime.utc_now())
    |> Map.put(:ai_results, %{
      "name" => "Analyzed Medicine",
      "dosage_form" => "tablet",
      "strength_value" => 500.0,
      "strength_unit" => "mg",
      "container_type" => "bottle",
      "total_quantity" => 30.0,
      "quantity_unit" => "tablets"
    })
  end

  def approved_batch_entry_factory do
    analyzed_batch_entry_factory()
    |> Map.put(:approval_status, :approved)
    |> Map.put(:reviewed_at, DateTime.utc_now())
    |> Map.put(:reviewed_by, "Test Reviewer")
  end

  def rejected_batch_entry_factory do
    analyzed_batch_entry_factory()
    |> Map.put(:approval_status, :rejected)
    |> Map.put(:reviewed_at, DateTime.utc_now())
    |> Map.put(:reviewed_by, "Test Reviewer")
    |> Map.put(:review_notes, "Medicine not clearly visible")
  end

  def failed_batch_entry_factory do
    batch_entry_factory()
    |> Map.put(:ai_analysis_status, :failed)
    |> Map.put(:error_message, "Analysis failed: Image quality too low")
  end

  def entry_image_factory do
    %EntryImage{
      batch_entry: build(:batch_entry),
      s3_key: sequence(:s3_key, &"uploads/test_medicine_#{&1}.jpg"),
      original_filename: sequence(:filename, &"medicine_photo_#{&1}.jpg"),
      # 1MB
      file_size: 1_024_000,
      content_type: "image/jpeg",
      upload_order: 0
    }
  end

  def png_entry_image_factory do
    entry_image_factory()
    |> Map.put(:s3_key, "uploads/test_medicine.png")
    |> Map.put(:original_filename, "medicine_photo.png")
    |> Map.put(:content_type, "image/png")
  end

  def large_entry_image_factory do
    entry_image_factory()
    # 10MB
    |> Map.put(:file_size, 10_000_000)
  end

  # Complex factory builders for testing workflows

  def batch_entry_with_images_factory do
    entry = build(:batch_entry)
    images = build_list(2, :entry_image, batch_entry: entry)
    %{entry | images: images}
  end

  def complete_batch_workflow_factory do
    entry = build(:approved_batch_entry)
    images = build_list(2, :entry_image, batch_entry: entry)
    %{entry | images: images}
  end

  # Traits for building variations

  def with_photos(%Entry{} = entry, count \\ 2) do
    images = build_list(count, :entry_image, batch_entry: entry)
    %{entry | images: images}
  end

  def with_analysis_results(%Entry{} = entry, results \\ %{}) do
    default_results = %{
      "name" => "Test Medicine",
      "dosage_form" => "tablet",
      "strength_value" => 500.0,
      "strength_unit" => "mg",
      "container_type" => "bottle",
      "total_quantity" => 30.0,
      "quantity_unit" => "tablets"
    }

    final_results = Map.merge(default_results, results)

    entry
    |> Map.put(:ai_analysis_status, :complete)
    |> Map.put(:ai_results, final_results)
    |> Map.put(:analyzed_at, DateTime.utc_now())
  end

  # Helper functions for test data creation

  def valid_medicine_attributes(attrs \\ %{}) do
    base_attrs = %{
      name: "Test Medicine",
      dosage_form: "tablet",
      strength_value: "10.0",
      strength_unit: "mg",
      container_type: "bottle",
      total_quantity: "30.0",
      quantity_unit: "tablets"
    }

    Map.merge(base_attrs, attrs)
  end

  def invalid_medicine_attributes do
    %{
      # Required field missing
      name: nil,
      # Invalid value
      dosage_form: "invalid_form",
      # Invalid number
      strength_value: -1,
      # Required field missing
      container_type: nil
    }
  end

  def create_test_image_file(filename \\ "test_medicine.jpg") do
    content = "fake image content"
    path = Path.join([System.tmp_dir(), filename])
    File.write!(path, content)
    path
  end

  def cleanup_test_files do
    upload_path = Application.get_env(:medpack, :upload_path)
    temp_path = Application.get_env(:medpack, :temp_upload_path)

    if File.exists?(upload_path), do: File.rm_rf!(upload_path)
    if File.exists?(temp_path), do: File.rm_rf!(temp_path)

    File.mkdir_p!(upload_path)
    File.mkdir_p!(temp_path)
  end
end
