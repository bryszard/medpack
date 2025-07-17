defmodule Medpack.BatchProcessingTest do
  use Medpack.DataCase, async: true

  alias Medpack.{BatchProcessing, Repo}
  alias Medpack.BatchProcessing.{Entry, EntryImage}

  describe "create_entry/1" do
    test "creates entry with valid attributes" do
      attrs = %{
        entry_number: 1
      }

      assert {:ok, entry} = BatchProcessing.create_entry(attrs)
      assert entry.entry_number == 1
      assert entry.status == :pending
      assert entry.ai_analysis_status == :pending
    end

    test "requires entry_number" do
      attrs = %{batch_id: "batch_123"}

      assert {:error, changeset} = BatchProcessing.create_entry(attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).entry_number
    end

    test "validates entry_number is positive" do
      attrs = %{
        batch_id: "batch_123",
        entry_number: 0
      }

      assert {:error, changeset} = BatchProcessing.create_entry(attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).entry_number
    end
  end

  describe "get_entry/1" do
    test "returns entry when it exists" do
      entry = insert(:batch_entry)

      result = BatchProcessing.get_entry(entry.id)

      assert result.id == entry.id
    end

    test "returns nil when entry does not exist" do
      result = BatchProcessing.get_entry(Ecto.UUID.generate())

      assert result == nil
    end
  end

  describe "get_entry!/1" do
    test "returns entry when it exists" do
      entry = insert(:batch_entry)

      result = BatchProcessing.get_entry!(entry.id)

      assert result.id == entry.id
    end

    test "raises when entry does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        BatchProcessing.get_entry!(Ecto.UUID.generate())
      end
    end
  end

  describe "update_entry/2" do
    test "updates entry with valid attributes" do
      entry = insert(:batch_entry)

      attrs = %{
        status: :processing,
        ai_analysis_status: :processing
      }

      assert {:ok, updated_entry} = BatchProcessing.update_entry(entry, attrs)
      assert updated_entry.status == :processing
      assert updated_entry.ai_analysis_status == :processing
    end

    test "can update AI analysis results" do
      entry = insert(:batch_entry)

      ai_results = %{
        "name" => "Test Medicine",
        "dosage_form" => "tablet",
        "strength_value" => 500.0,
        "strength_unit" => "mg"
      }

      attrs = %{
        ai_analysis_status: :complete,
        ai_results: ai_results,
        analyzed_at: DateTime.utc_now()
      }

      assert {:ok, updated_entry} = BatchProcessing.update_entry(entry, attrs)
      assert updated_entry.ai_analysis_status == :complete
      assert updated_entry.ai_results == ai_results
      assert updated_entry.analyzed_at != nil
    end

    test "can set error status and message" do
      entry = insert(:batch_entry)

      attrs = %{
        ai_analysis_status: :failed,
        error_message: "Analysis failed: Image too blurry"
      }

      assert {:ok, updated_entry} = BatchProcessing.update_entry(entry, attrs)
      assert updated_entry.ai_analysis_status == :failed
      assert updated_entry.error_message == "Analysis failed: Image too blurry"
    end
  end

  describe "delete_entry/1" do
    test "deletes entry successfully" do
      entry = insert(:batch_entry)

      assert {:ok, deleted_entry} = BatchProcessing.delete_entry(entry)
      assert deleted_entry.id == entry.id
      assert BatchProcessing.get_entry(entry.id) == nil
    end

    test "deletes associated images when entry is deleted" do
      entry = insert(:batch_entry)
      image1 = insert(:entry_image, batch_entry: entry)
      image2 = insert(:entry_image, batch_entry: entry)

      assert {:ok, _deleted_entry} = BatchProcessing.delete_entry(entry)

      # Images should be deleted too
      assert Repo.get(EntryImage, image1.id) == nil
      assert Repo.get(EntryImage, image2.id) == nil
    end
  end

  describe "list_ready_for_analysis/0" do
    test "returns entries that have photos and are pending analysis" do
      # Entry with photos and pending analysis (should be included)
      ready_entry = insert(:batch_entry, ai_analysis_status: :pending)
      insert(:entry_image, batch_entry: ready_entry)

      # Entry without photos (should not be included)
      _no_photos_entry = insert(:batch_entry, ai_analysis_status: :pending)

      # Entry with photos but already processing (should not be included)
      processing_entry = insert(:batch_entry, ai_analysis_status: :processing)
      insert(:entry_image, batch_entry: processing_entry)

      # Entry with photos but already complete (should not be included)
      complete_entry = insert(:batch_entry, ai_analysis_status: :complete)
      insert(:entry_image, batch_entry: complete_entry)

      ready_entries = BatchProcessing.list_ready_for_analysis()

      assert length(ready_entries) == 1
      assert hd(ready_entries).id == ready_entry.id
    end

    test "preloads images association" do
      entry = insert(:batch_entry, ai_analysis_status: :pending)
      image = insert(:entry_image, batch_entry: entry)

      ready_entries = BatchProcessing.list_ready_for_analysis()

      assert length(ready_entries) == 1
      entry = hd(ready_entries)
      assert length(entry.images) == 1
      assert hd(entry.images).id == image.id
    end
  end

  describe "create_entry_image/1" do
    test "creates image with valid attributes" do
      entry = insert(:batch_entry)

      attrs = %{
        batch_entry_id: entry.id,
        s3_key: "uploads/test_image.jpg",
        original_filename: "test_image.jpg",
        file_size: 1_024_000,
        content_type: "image/jpeg",
        upload_order: 0
      }

      assert {:ok, image} = BatchProcessing.create_entry_image(attrs)
      assert image.batch_entry_id == entry.id
      assert image.s3_key == "uploads/test_image.jpg"
      assert image.original_filename == "test_image.jpg"
      assert image.file_size == 1_024_000
      assert image.content_type == "image/jpeg"
      assert image.upload_order == 0
    end

    test "requires batch_entry_id" do
      attrs = %{
        s3_key: "uploads/test_image.jpg",
        original_filename: "test_image.jpg"
      }

      assert {:error, changeset} = BatchProcessing.create_entry_image(attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).batch_entry_id
    end

    test "requires s3_key" do
      entry = insert(:batch_entry)

      attrs = %{
        batch_entry_id: entry.id,
        original_filename: "test_image.jpg"
      }

      assert {:error, changeset} = BatchProcessing.create_entry_image(attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).s3_key
    end

    test "requires original_filename" do
      entry = insert(:batch_entry)

      attrs = %{
        batch_entry_id: entry.id,
        s3_key: "uploads/test_image.jpg"
      }

      assert {:error, changeset} = BatchProcessing.create_entry_image(attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).original_filename
    end

    test "validates content_type inclusion" do
      entry = insert(:batch_entry)

      attrs = %{
        batch_entry_id: entry.id,
        s3_key: "uploads/test_image.jpg",
        original_filename: "test_image.jpg",
        # Invalid content type
        content_type: "text/plain"
      }

      assert {:error, changeset} = BatchProcessing.create_entry_image(attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).content_type
    end

    test "validates file_size is positive" do
      entry = insert(:batch_entry)

      attrs = %{
        batch_entry_id: entry.id,
        s3_key: "uploads/test_image.jpg",
        original_filename: "test_image.jpg",
        file_size: 0
      }

      assert {:error, changeset} = BatchProcessing.create_entry_image(attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).file_size
    end

    test "validates upload_order is non-negative" do
      entry = insert(:batch_entry)

      attrs = %{
        batch_entry_id: entry.id,
        s3_key: "uploads/test_image.jpg",
        original_filename: "test_image.jpg",
        upload_order: -1
      }

      assert {:error, changeset} = BatchProcessing.create_entry_image(attrs)
      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).upload_order
    end
  end

  describe "list_entry_images/1" do
    test "returns images for specific entry ordered by upload_order" do
      entry = insert(:batch_entry)
      image1 = insert(:entry_image, batch_entry: entry, upload_order: 2)
      image2 = insert(:entry_image, batch_entry: entry, upload_order: 0)
      image3 = insert(:entry_image, batch_entry: entry, upload_order: 1)

      # Image from different entry
      other_entry = insert(:batch_entry)
      _other_image = insert(:entry_image, batch_entry: other_entry)

      images = BatchProcessing.list_entry_images(entry.id)

      assert length(images) == 3
      # upload_order 0
      assert Enum.at(images, 0).id == image2.id
      # upload_order 1
      assert Enum.at(images, 1).id == image3.id
      # upload_order 2
      assert Enum.at(images, 2).id == image1.id
    end

    test "returns empty list for entry with no images" do
      entry = insert(:batch_entry)

      images = BatchProcessing.list_entry_images(entry.id)

      assert images == []
    end
  end

  describe "delete_entry_image/1" do
    test "deletes image successfully" do
      image = insert(:entry_image)

      assert {:ok, deleted_image} = BatchProcessing.delete_entry_image(image)
      assert deleted_image.id == image.id
      assert Repo.get(EntryImage, image.id) == nil
    end
  end

  describe "change_entry/2" do
    test "returns changeset for entry" do
      entry = insert(:batch_entry)

      changeset = BatchProcessing.change_entry(entry)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data == entry
    end

    test "returns changeset with changes applied" do
      entry = insert(:batch_entry)
      attrs = %{status: :processing}

      changeset = BatchProcessing.change_entry(entry, attrs)

      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.status == :processing
    end
  end

  describe "Entry helper functions" do
    test "has_photos?/1 returns true when entry has images" do
      entry = insert(:batch_entry)
      insert(:entry_image, batch_entry: entry)

      # Test with preloaded images
      entry_with_images = entry |> Repo.preload(:images)
      assert Entry.has_photos?(entry_with_images) == true

      # Test without preloaded images (queries database)
      assert Entry.has_photos?(entry) == true
    end

    test "has_photos?/1 returns false when entry has no images" do
      entry = insert(:batch_entry)

      # Test with preloaded images
      entry_with_images = entry |> Repo.preload(:images)
      assert Entry.has_photos?(entry_with_images) == false

      # Test without preloaded images (queries database)
      assert Entry.has_photos?(entry) == false
    end

    test "ready_for_analysis?/1 returns true when entry has photos and is pending analysis" do
      entry = insert(:batch_entry, ai_analysis_status: :pending)
      insert(:entry_image, batch_entry: entry)
      entry = entry |> Repo.preload(:images)

      assert Entry.ready_for_analysis?(entry) == true
    end

    test "ready_for_analysis?/1 returns false when entry has no photos" do
      entry = insert(:batch_entry, ai_analysis_status: :pending)
      entry = entry |> Repo.preload(:images)

      assert Entry.ready_for_analysis?(entry) == false
    end

    test "ready_for_analysis?/1 returns false when entry is not pending analysis" do
      entry = insert(:batch_entry, ai_analysis_status: :complete)
      insert(:entry_image, batch_entry: entry)
      entry = entry |> Repo.preload(:images)

      assert Entry.ready_for_analysis?(entry) == false
    end

    test "analysis_complete?/1 returns true when analysis is complete with results" do
      entry = insert(:analyzed_batch_entry)

      assert Entry.analysis_complete?(entry) == true
    end

    test "analysis_complete?/1 returns false when analysis status is not complete" do
      entry = insert(:batch_entry, ai_analysis_status: :pending)

      assert Entry.analysis_complete?(entry) == false
    end

    test "analysis_complete?/1 returns false when analysis is complete but no results" do
      entry =
        insert(:batch_entry,
          ai_analysis_status: :complete,
          ai_results: nil
        )

      assert Entry.analysis_complete?(entry) == false
    end
  end
end
