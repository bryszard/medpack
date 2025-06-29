# Medicine Inventory App Rebuild Plan

## Current State Analysis

The app currently has:

- **Root route (`/`)**: MedicineLive - Shows inventory with "Add Medicine" form capability
- **Batch route (`/batch`)**: BatchMedicineLive - Batch processing of medicines with AI photo analysis
- **Home route (unused)**: PageController with static home template

## Target State

We want to restructure the app to have:

- **Root route (`/`)**: Landing page with navigation to `/inventory` and `/add`
- **Inventory route (`/inventory`)**: Current MedicineLive view but WITHOUT "Add Medicine" capability
- **Add route (`/add`)**: Current BatchMedicineLive view (batch mode for adding medicines)

## Implementation Plan

### Phase 1: Router and Route Updates

- [x] Update router.ex to change route structure:
  - [x] Change root route `/` to use PageController (landing page)
  - [x] Add `/inventory` route to use MedicineLive
  - [x] Change `/batch` route to `/add` using BatchMedicineLive
  - [x] Update any internal navigation links

### Phase 2: Landing Page Creation

- [x] Update PageController home template to be a proper landing page
- [x] Create navigation buttons/links to `/inventory` and `/add`
- [x] Design should be consistent with the app's medical theme
- [x] Remove the current static medicine list (since it will be in `/inventory`)

### Phase 3: Inventory View Modifications

- [x] Remove "Add Medicine" form and toggle functionality from MedicineLive
- [x] Remove the "Toggle Form" button and related UI
- [x] Remove all form-related assigns and event handlers:
  - [x] Remove `:show_form` assign
  - [x] Remove `:form` assign
  - [x] Remove upload-related functionality (photos, AI analysis)
  - [x] Remove `handle_event("toggle_form")`, `handle_event("save")`, etc.
- [x] Keep only the inventory display and search functionality
- [x] Update navigation to show link to `/add` instead of inline form
- [x] Clean up the template to focus on inventory viewing only

### Phase 4: Add/Batch View Updates

- [x] Update BatchMedicineLive route from `/batch` to `/add`
- [x] Update navigation links within BatchMedicineLive template
- [x] Update any references to "batch mode" to be more focused on "adding medicines"
- [x] Ensure the "View Inventory" link points to `/inventory`

### Phase 5: Navigation Consistency

- [x] Update all internal navigation links across templates:
  - [x] MedicineLive template navigation
  - [x] BatchMedicineLive template navigation
  - [x] Any other cross-references
- [x] Ensure consistent styling and user experience across all pages

### Phase 6: Testing and Cleanup

- [x] Test all routes work correctly
- [x] Test navigation between pages works
- [x] Verify inventory functionality still works (search, display)
- [x] Verify batch/add functionality still works
- [x] Clean up any unused code or assigns
- [x] Update any documentation or comments

## Technical Details

### Files to Modify:

1. `lib/medicine_inventory_web/router.ex` - Route changes
2. `lib/medicine_inventory_web/controllers/page_html/home.html.heex` - Landing page
3. `lib/medicine_inventory_web/live/medicine_live.ex` - Remove add functionality
4. `lib/medicine_inventory_web/live/medicine_live.html.heex` - Remove form UI
5. `lib/medicine_inventory_web/live/batch_medicine_live.html.heex` - Update navigation

### Key Changes:

- **Router**: `/` → PageController, `/inventory` → MedicineLive, `/add` → BatchMedicineLive
- **MedicineLive**: Remove form, uploads, AI analysis - keep only inventory display
- **Landing Page**: Add proper navigation to inventory and add pages
- **Navigation**: Update all cross-page links to use new routes

### Considerations:

- Maintain all existing functionality, just reorganize the UI flow
- Keep the same styling and design language
- Ensure the medicine creation flow (batch mode) remains fully functional
- Preserve the inventory viewing and searching capabilities

## ✅ Implementation Complete!

All phases have been successfully completed. The Medicine Inventory app has been rebuilt with the new navigation structure:

- **Landing Page (`/`)**: Clean welcome page with navigation to inventory and add pages
- **Inventory (`/inventory`)**: View-only medicine inventory with search functionality
- **Add Medicines (`/add`)**: Batch medicine processing with AI photo analysis

The app maintains all existing functionality while providing a cleaner, more organized user flow.
