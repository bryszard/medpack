# Medicine Inventory App Plan

## Overview
A warm and friendly home medicine inventory app with AI-powered photo recognition.

## Detailed Steps
- [x] Generate Phoenix LiveView project called `medicine_inventory`
- [x] Start the server so we can follow along
- [x] Replace home page with static mockup of warm, friendly design
- [x] Add dependencies for image upload and AI integration
  - `:live_view_upload` for file uploads
  - `:req` for API calls (already included)
  - `:image` for image processing
- [x] Create Medicine context and schema
  - Medicine table: name, type, quantity, expiration_date, photo_path, notes
  - Migration for medicines table
- [x] Implement MedicineInventoryLive with photo upload
  - Photo upload functionality
  - Form for manual entry/editing
  - Integration with multi-modal AI (OpenAI GPT-4 Vision or similar)
- [x] Create inventory list view with warm, friendly design
  - Display all medicines with photos
  - Search and filter capabilities
  - Expiration date alerts with friendly warnings
- [x] Update layouts to match warm, friendly theme
  - Customize app.css with warm colors
  - Update root.html.heex and Layouts.app
- [x] Update router with main inventory route
- [x] Test complete workflow and verify functionality

