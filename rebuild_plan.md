# Medicine Inventory App Rebuild Plan

## Overview

Refactor the batch medicine processing to use real OpenAI integration with background jobs via Oban, while moving business logic from the LiveView to the backend context.

## Current State Analysis

- **Large LiveView**: `BatchMedicineLive` is 491 lines and handles everything
- **Simulated AI**: Currently uses fake responses instead of real OpenAI API
- **No Background Jobs**: All processing happens synchronously in LiveView
- **Missing Dependencies**: Need `oban`, `ex_openai`, and proper file handling
- **Monolithic Structure**: Business logic mixed with presentation logic

## Dependencies to Add

### Phase 1: Core Dependencies

- [x] Add `oban` for background job processing
- [x] Add `ex_openai` for OpenAI API integration
- [x] Add `hackney` or `finch` for HTTP client (if not already included)
- [x] Add `jason` for JSON handling (already present)
- [x] Add `temp` for temporary file handling

### Phase 2: Configuration

- [x] Configure Oban in `config/config.exs`
- [x] Configure Oban queues and workers
- [x] Set up OpenAI API key configuration
- [x] Configure file upload storage paths
- [x] Add Oban to supervision tree

## Backend Refactoring (MedicineInventory Context)

### Phase 3: New Modules

- [x] Create `MedicineInventory.BatchProcessing` context
- [x] Create `MedicineInventory.AI.ImageAnalyzer` module
- [x] Create `MedicineInventory.Jobs.AnalyzeMedicinePhotoJob` Oban worker
- [x] Create `MedicineInventory.FileManager` for upload handling
- [x] Create `MedicineInventory.BatchProcessing.Entry` schema

### Phase 4: Database Changes

- [x] Create `batch_entries` table migration
- [x] Add indexes for batch processing queries
- [x] Add file path storage for uploaded images
- [x] Add batch processing status tracking

### Phase 5: Business Logic Migration

- [x] Move batch entry creation logic to `BatchProcessing` context
- [x] Move AI analysis logic to dedicated modules
- [x] Implement real OpenAI image analysis
- [x] Add error handling and retry logic
- [x] Add progress tracking for batch operations

## AI Integration

### Phase 6: OpenAI Integration

- [x] Implement `ImageAnalyzer.analyze_medicine_photo/1`
- [x] Create proper prompts for medicine identification
- [x] Handle OpenAI API responses and errors
- [x] Implement rate limiting and retries
- [x] Add image preprocessing if needed
- [x] Validate and sanitize AI responses

### Phase 7: Background Job Processing

- [x] Create `AnalyzeMedicinePhotoJob` with proper error handling
- [x] Implement job progress tracking
- [x] Add job retry logic with exponential backoff
- [x] Create job status broadcasting to LiveView
- [x] Handle job failures gracefully

## Frontend Refactoring (MedicineInventoryWeb)

### Phase 8: LiveView Simplification

- [x] Reduce `BatchMedicineLive` to UI logic only
- [x] Remove simulated AI analysis code
- [x] Implement real-time job progress updates
- [x] Add proper error handling and user feedback
- [x] Improve upload handling with progress indicators

### Phase 9: Real-time Updates

- [x] Implement Phoenix PubSub for job status updates
- [x] Add real-time progress bars for batch processing
- [x] Show individual entry processing status
- [x] Handle connection drops and reconnections
- [x] Add proper loading states

## File Handling

### Phase 10: File Management

- [x] Implement secure file upload handling
- [x] Add file validation (size, type, etc.)
- [x] Create temporary file cleanup jobs
- [x] Implement file storage organization
- [ ] Add image optimization/resizing if needed

## Testing & Quality

### Phase 11: Testing

- [ ] Add tests for `BatchProcessing` context
- [ ] Add tests for `ImageAnalyzer` module
- [ ] Add tests for Oban jobs
- [ ] Add integration tests for full batch flow
- [ ] Add tests for error scenarios

### Phase 12: Error Handling & Monitoring

- [ ] Add comprehensive error logging
- [ ] Implement job failure notifications
- [ ] Add monitoring for OpenAI API usage
- [ ] Add rate limiting protection
- [ ] Implement graceful degradation

## Configuration & Environment

### Phase 13: Environment Setup

- [ ] Add OpenAI API key to environment variables
- [ ] Configure proper file upload limits
- [ ] Set up development vs production configs
- [ ] Add proper logging configuration
- [ ] Configure Oban dashboard access

## Performance & Optimization

### Phase 14: Performance

- [ ] Optimize image upload and processing
- [ ] Add caching for repeated analyses
- [ ] Implement batch size limits
- [ ] Add memory usage monitoring
- [ ] Optimize database queries

## Documentation & Cleanup

### Phase 15: Final Steps

- [ ] Update README with new setup instructions
- [ ] Document OpenAI integration requirements
- [ ] Clean up unused code and dependencies
- [ ] Add API documentation
- [ ] Create deployment guide

## Implementation Order

1. **Setup Phase** (1-2): Add dependencies and basic configuration
2. **Backend Phase** (3-5): Create new backend modules and database changes
3. **AI Phase** (6-7): Implement real OpenAI integration with background jobs
4. **Frontend Phase** (8-9): Refactor LiveView and add real-time updates
5. **Polish Phase** (10-15): File handling, testing, monitoring, and documentation

## Key Technical Decisions

- **Oban Queues**: Use separate queues for different job types (analysis, cleanup, etc.)
- **File Storage**: Store uploaded files temporarily, clean up after processing
- **Error Handling**: Implement circuit breaker pattern for OpenAI API calls
- **Progress Tracking**: Use Phoenix PubSub for real-time progress updates
- **Image Processing**: Send images directly to OpenAI Vision API
- **Database**: Keep existing SQLite for simplicity, add batch processing tables

## Success Criteria

- [ ] Batch medicine processing works with real OpenAI API
- [ ] Background jobs handle image analysis asynchronously
- [ ] LiveView shows real-time progress and updates
- [ ] Error handling provides meaningful user feedback
- [ ] File uploads are secure and properly managed
- [ ] System is resilient to API failures and network issues
