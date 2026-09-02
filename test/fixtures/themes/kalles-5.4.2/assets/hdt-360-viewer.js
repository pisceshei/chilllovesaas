/**
 * 360 Product Viewer Component
 * Features: Autoplay, Pause/Play, Prev/Next navigation, Mobile swipe support
 */

class HDT360Viewer extends HTMLElement {
  constructor() {
    super();
    
    // Configuration
    this.currentFrame = 0;
    this.isPlaying = false;
    this.autoplaySpeed = parseInt(this.dataset.autoplaySpeed) || 100;
    this.autoplayEnabled = this.dataset.autoplay === 'true';
    this.isRTL = this.dataset.rtl === 'true';
    this.buttonStepSize = parseInt(this.dataset.buttonStep) || 2; // Number of frames to move when clicking prev/next
    this.buttonStepSpeed = parseInt(this.dataset.buttonStepSpeed) || 60; // Milliseconds between frames during button click animation
    this.animationFrame = null;
    this.lastFrameTime = 0;
    
    // Touch/Mouse tracking
    this.isDragging = false;
    this.startX = 0;
    this.currentX = 0;
    this.dragThreshold = 5;
    this.hasMoved = false; // Track if user actually moved during drag
    
    // Elements
    this.frames = [];
    this.playPauseBtn = null;
    this.prevBtn = null;
    this.nextBtn = null;
    this.scrubberThumb = null;
    this.scrubberTrack = null;
    this.scrubberProgress = null;
    
    // Scrubber tracking
    this.isScrubbing = false;
    
    // Intersection Observer for autoplay when in viewport
    this.observer = null;
    this.isInViewport = false;
    
    // Button step animation
    this.isAnimatingStep = false;
    this.stepAnimationTimer = null;
    
    // Loading state
    this.isLoading = true;
    this.loadedFrames = 0;
    this.loadingOverlay = null;
  }
  
  connectedCallback() {
    this.frames = Array.from(this.querySelectorAll('.hdt-360-frame'));
    this.totalFrames = this.frames.length;
    
    if (this.totalFrames === 0) return;
    
    // Create and show loading overlay
    this.createLoadingOverlay();
    
    // Auto-detect RTL if not explicitly set
    if (!this.dataset.rtl) {
      const isDocumentRTL = document.dir === 'rtl' || 
                           document.documentElement.dir === 'rtl' || 
                           getComputedStyle(this).direction === 'rtl';
      this.isRTL = isDocumentRTL;
      this.dataset.rtl = this.isRTL.toString();
    }
    
    // Get control buttons
    this.playPauseBtn = this.querySelector('.hdt-360-play-pause');
    this.prevBtn = this.querySelector('.hdt-360-prev');
    this.nextBtn = this.querySelector('.hdt-360-next');
    
    // Get scrubber elements
    this.scrubberThumb = this.querySelector('.hdt-360-scrubber-thumb');
    this.scrubberTrack = this.querySelector('.hdt-360-scrubber-track');
    this.scrubberProgress = this.querySelector('.hdt-360-scrubber-progress');
    
    // Show first frame
    this.showFrame(0);
    
    // Preload all images and track loading progress
    this.preloadImages();
    
    // Bind events
    this.bindEvents();
    
    // Setup Intersection Observer for viewport visibility
    this.setupIntersectionObserver();
    
    // Handle page visibility (tab switching)
    this.handleVisibilityChange = this.handleVisibilityChange.bind(this);
    document.addEventListener('visibilitychange', this.handleVisibilityChange);
    
    // Set initial paused state
    if (!this.autoplayEnabled) {
      this.classList.add('is-paused');
    }
  }
  
  createLoadingOverlay() {
    // Create loading overlay
    this.loadingOverlay = document.createElement('div');
    this.loadingOverlay.className = 'hdt-360-loading-overlay';
    this.loadingOverlay.innerHTML = `
      <div class="hdt-360-loading-spinner">
        <svg class="hdt-360-spinner-icon" viewBox="0 0 50 50">
          <circle class="hdt-360-spinner-path" cx="25" cy="25" r="20" fill="none" stroke-width="4"></circle>
        </svg>
        <div class="hdt-360-loading-text">...</div>
        <div class="hdt-360-loading-progress">
          <div class="hdt-360-loading-bar" style="width: 0%"></div>
        </div>
      </div>
    `;
    this.appendChild(this.loadingOverlay);
    this.classList.add('is-loading');
  }
  
  updateLoadingProgress() {
    if (!this.loadingOverlay) return;
    
    const percentage = Math.round((this.loadedFrames / this.totalFrames) * 100);
    const progressBar = this.loadingOverlay.querySelector('.hdt-360-loading-bar');
    const loadingText = this.loadingOverlay.querySelector('.hdt-360-loading-text');
    
    if (progressBar) {
      progressBar.style.width = `${percentage}%`;
    }
    
    if (loadingText) {
      loadingText.textContent = `${percentage}%`;
    }
  }
  
  hideLoadingOverlay() {
    if (!this.loadingOverlay) return;
    
    this.loadingOverlay.classList.add('fade-out');
    this.classList.remove('is-loading');
    
    setTimeout(() => {
      if (this.loadingOverlay && this.loadingOverlay.parentNode) {
        this.loadingOverlay.remove();
        this.loadingOverlay = null;
      }
    }, 300); // Match fade-out animation duration
  }
  
  preloadImages() {
    this.loadedFrames = 0;
    
    this.frames.forEach((frame, index) => {
      if (frame.complete && frame.naturalHeight !== 0) {
        // Image already loaded
        this.loadedFrames++;
        this.updateLoadingProgress();
      } else {
        // Wait for image to load
        frame.addEventListener('load', () => {
          this.loadedFrames++;
          this.updateLoadingProgress();
          this.checkAllImagesLoaded();
        }, { once: true });
        
        frame.addEventListener('error', () => {
          console.error(`Failed to load frame ${index + 1}`);
          this.loadedFrames++;
          this.updateLoadingProgress();
          this.checkAllImagesLoaded();
        }, { once: true });
      }
    });
    
    // Check if all images are already loaded
    this.checkAllImagesLoaded();
  }
  
  checkAllImagesLoaded() {
    if (this.loadedFrames >= this.totalFrames) {
      this.isLoading = false;
      this.hideLoadingOverlay();
      
      // Start autoplay if enabled and in viewport
      if (this.autoplayEnabled && (this.isInViewport || !this.observer)) {
        setTimeout(() => {
          this.play();
        }, 500); // Small delay after loading completes
      }
    }
  }
  
  showLoadingMessage() {
    // Shake the loading overlay to indicate it's still loading
    if (this.loadingOverlay) {
      this.loadingOverlay.classList.add('shake');
      setTimeout(() => {
        if (this.loadingOverlay) {
          this.loadingOverlay.classList.remove('shake');
        }
      }, 500);
    }
  }
  
  disconnectedCallback() {
    this.pause();
    this.unbindEvents();
    
    // Cleanup Intersection Observer
    if (this.observer) {
      this.observer.disconnect();
      this.observer = null;
    }
    
    // Cleanup visibility change listener
    document.removeEventListener('visibilitychange', this.handleVisibilityChange);
    
    // Cleanup step animation timer
    if (this.stepAnimationTimer) {
      clearTimeout(this.stepAnimationTimer);
      this.stepAnimationTimer = null;
    }
  }
  
  setupIntersectionObserver() {
    // Create Intersection Observer to track visibility
    const options = {
      root: null, // viewport
      rootMargin: '0px',
      threshold: 0.1 // Trigger when at least 10% of element is visible
    };
    
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        this.isInViewport = entry.isIntersecting;
        
        if (this.autoplayEnabled) {
          if (entry.isIntersecting) {
            // Element is in viewport - start autoplay
            if (!this.isPlaying && !this.isDragging && !this.isScrubbing) {
              this.play();
            }
          } else {
            // Element is out of viewport - pause autoplay
            if (this.isPlaying) {
              this.pause();
            }
          }
        }
      });
    }, options);
    
    this.observer.observe(this);
  }
  
  handleVisibilityChange() {
    if (document.hidden) {
      // Page/tab is hidden - pause autoplay
      if (this.isPlaying) {
        this.pause();
      }
    } else {
      // Page/tab is visible again - resume autoplay if enabled and in viewport
      if (this.autoplayEnabled && this.isInViewport && !this.isPlaying) {
        this.play();
      }
    }
  }
  
  bindEvents() {
    // Play/Pause button
    if (this.playPauseBtn) {
      this.playPauseBtn.addEventListener('click', this.handlePlayPauseClick.bind(this));
    }
    
    // Prev/Next buttons
    if (this.prevBtn) {
      this.prevBtn.addEventListener('click', this.handlePrevClick.bind(this));
    }
    if (this.nextBtn) {
      this.nextBtn.addEventListener('click', this.handleNextClick.bind(this));
    }
    
    // Mouse events
    // this.addEventListener('mousedown', this.handleDragStart.bind(this));
    // this.addEventListener('mousemove', this.handleDragMove.bind(this));
    // this.addEventListener('mouseup', this.handleDragEnd.bind(this));
    // this.addEventListener('mouseleave', this.handleDragEnd.bind(this));
    
    // Touch events
    // this.addEventListener('touchstart', this.handleDragStart.bind(this), { passive: true });
    // this.addEventListener('touchmove', this.handleDragMove.bind(this), { passive: true });
    // this.addEventListener('touchend', this.handleDragEnd.bind(this));
    // this.addEventListener('touchcancel', this.handleDragEnd.bind(this));
    
    // Prevent context menu on long press
    this.addEventListener('contextmenu', (e) => {
      if (this.isDragging) {
        e.preventDefault();
      }
    });
    
    // Scrubber events
    if (this.scrubberThumb) {
      this.scrubberThumb.addEventListener('mousedown', this.handleScrubberStart.bind(this));
      this.scrubberThumb.addEventListener('touchstart', this.handleScrubberStart.bind(this), { passive: true });
    }
    
    if (this.scrubberTrack) {
      this.scrubberTrack.addEventListener('click', this.handleTrackClick.bind(this));
    }
    
    // Global events for scrubbing
    document.addEventListener('mousemove', this.handleScrubberMove.bind(this));
    document.addEventListener('mouseup', this.handleScrubberEnd.bind(this));
    document.addEventListener('touchmove', this.handleScrubberMove.bind(this), { passive: true });
    document.addEventListener('touchend', this.handleScrubberEnd.bind(this));
  }
  
  unbindEvents() {
    if (this.playPauseBtn) {
      this.playPauseBtn.removeEventListener('click', this.handlePlayPauseClick.bind(this));
    }
    if (this.prevBtn) {
      this.prevBtn.removeEventListener('click', this.handlePrevClick.bind(this));
    }
    if (this.nextBtn) {
      this.nextBtn.removeEventListener('click', this.handleNextClick.bind(this));
    }
    
    // Remove scrubber events
    if (this.scrubberThumb) {
      this.scrubberThumb.removeEventListener('mousedown', this.handleScrubberStart.bind(this));
      this.scrubberThumb.removeEventListener('touchstart', this.handleScrubberStart.bind(this));
    }
    
    if (this.scrubberTrack) {
      this.scrubberTrack.removeEventListener('click', this.handleTrackClick.bind(this));
    }
    
    document.removeEventListener('mousemove', this.handleScrubberMove.bind(this));
    document.removeEventListener('mouseup', this.handleScrubberEnd.bind(this));
    document.removeEventListener('touchmove', this.handleScrubberMove.bind(this));
    document.removeEventListener('touchend', this.handleScrubberEnd.bind(this));
  }
  
  handlePlayPauseClick(e) {
    e.preventDefault();
    e.stopPropagation();
    
    // Prevent action if still loading
    if (this.isLoading) {
      this.showLoadingMessage();
      return;
    }
    
    this.togglePlayPause();
  }
  
  handlePrevClick(e) {
    e.preventDefault();
    e.stopPropagation();
    
    // Prevent action if still loading
    if (this.isLoading) {
      this.showLoadingMessage();
      return;
    }
    
    if (this.isAnimatingStep) return; // Prevent clicks during animation
    
    // Pause autoplay if it's running and save state
    const wasPlaying = this.isPlaying;
    if (wasPlaying) {
      this.pause();
    }
    
    // Add visual feedback class
    this.classList.add('button-click');
    
    // In RTL, prev button should go next (since it's on the right)
    // Use animated step for smooth frame-by-frame transition
    if (this.isRTL) {
      this.nextFrameStep(wasPlaying);
    } else {
      this.prevFrameStep(wasPlaying);
    }
    
    // Remove class after animation completes
    setTimeout(() => {
      this.classList.remove('button-click');
    }, this.buttonStepSize * this.buttonStepSpeed + 50); // Duration based on steps
  }
  
  handleNextClick(e) {
    e.preventDefault();
    e.stopPropagation();
    
    // Prevent action if still loading
    if (this.isLoading) {
      this.showLoadingMessage();
      return;
    }
    
    if (this.isAnimatingStep) return; // Prevent clicks during animation
    
    // Pause autoplay if it's running and save state
    const wasPlaying = this.isPlaying;
    if (wasPlaying) {
      this.pause();
    }
    
    // Add visual feedback class
    this.classList.add('button-click');
    
    // In RTL, next button should go prev (since it's on the left)
    // Use animated step for smooth frame-by-frame transition
    if (this.isRTL) {
      this.prevFrameStep(wasPlaying);
    } else {
      this.nextFrameStep(wasPlaying);
    }
    
    // Remove class after animation completes
    setTimeout(() => {
      this.classList.remove('button-click');
    }, this.buttonStepSize * this.buttonStepSpeed + 50); // Duration based on steps
  }
  
  handleScrubberStart(e) {
    e.preventDefault();
    e.stopPropagation();
    
    // Prevent scrubbing if still loading
    if (this.isLoading) {
      this.showLoadingMessage();
      return;
    }
    
    this.isScrubbing = true;
    this.scrubberThumb.classList.add('is-dragging');
    
    // Pause autoplay when scrubbing
    if (this.isPlaying) {
      this.pause();
      this.wasPlayingBeforeScrub = true;
    } else {
      this.wasPlayingBeforeScrub = false;
    }
  }
  
  handleScrubberMove(e) {
    if (!this.isScrubbing) return;
    
    const touch = e.touches ? e.touches[0] : e;
    const rect = this.scrubberTrack.getBoundingClientRect();
    const x = touch.clientX - rect.left;
    let percentage = Math.max(0, Math.min(1, x / rect.width));
    
    // Reverse percentage for RTL
    if (this.isRTL) {
      percentage = 1 - percentage;
    }
    
    const frameIndex = Math.round(percentage * (this.totalFrames - 1));
    
    this.goToFrame(frameIndex);
  }
  
  handleScrubberEnd(e) {
    if (!this.isScrubbing) return;
    
    this.isScrubbing = false;
    this.scrubberThumb.classList.remove('is-dragging');
    
    // Resume autoplay if it was playing before and element is in viewport
    if (this.wasPlayingBeforeScrub && this.isInViewport) {
      setTimeout(() => {
        this.play();
      }, 500);
    }
  }
  
  handleTrackClick(e) {
    // Don't handle if clicking on thumb
    if (e.target.closest('.hdt-360-scrubber-thumb')) {
      return;
    }
    
    // Prevent action if still loading
    if (this.isLoading) {
      this.showLoadingMessage();
      return;
    }
    
    const rect = this.scrubberTrack.getBoundingClientRect();
    const x = e.clientX - rect.left;
    let percentage = Math.max(0, Math.min(1, x / rect.width));
    
    // Reverse percentage for RTL
    if (this.isRTL) {
      percentage = 1 - percentage;
    }
    
    const frameIndex = Math.round(percentage * (this.totalFrames - 1));
    
    this.goToFrame(frameIndex);
  }
  
  handleDragStart(e) {
    // Ignore if clicking on control buttons or scrubber
    if (e.target.closest('.hdt-360-play-pause, .hdt-360-prev, .hdt-360-next, .hdt-360-scrubber')) {
      return;
    }
    
    // Prevent drag if still loading
    if (this.isLoading) {
      this.showLoadingMessage();
      return;
    }
    
    const touch = e.touches ? e.touches[0] : e;
    this.isDragging = true;
    this.hasMoved = false;
    this.startX = touch.clientX;
    this.currentX = touch.clientX;
    this.classList.add('is-dragging');
    
    // Pause autoplay when user starts dragging
    if (this.isPlaying) {
      this.pause();
      this.wasPlayingBeforeDrag = true;
    } else {
      this.wasPlayingBeforeDrag = false;
    }
  }
  
  handleDragMove(e) {
    if (!this.isDragging) return;
    
    const touch = e.touches ? e.touches[0] : e;
    this.currentX = touch.clientX;
    const deltaX = this.currentX - this.startX;
    
    // Calculate how many frames to move based on drag distance
    const sensitivity = 2; // Pixels per frame
    const framesToMove = Math.floor(Math.abs(deltaX) / sensitivity);
    
    if (framesToMove > 0) {
      this.hasMoved = true; // User has actually dragged
      
      // Determine direction based on RTL setting
      const isMovingRight = this.isRTL ? (deltaX < 0) : (deltaX > 0);
      
      if (isMovingRight) {
        // Moving right (or left in RTL) - next frame
        this.goToFrame((this.currentFrame + framesToMove) % this.totalFrames);
      } else {
        // Moving left (or right in RTL) - previous frame
        this.goToFrame((this.currentFrame - framesToMove + this.totalFrames) % this.totalFrames);
      }
      this.startX = this.currentX;
    }
  }
  
  handleDragEnd(e) {
    if (!this.isDragging) return;
    
    this.isDragging = false;
    this.classList.remove('is-dragging');
    
    // Only resume autoplay if user actually dragged (not just a click) and element is in viewport
    if (this.wasPlayingBeforeDrag && this.hasMoved && this.isInViewport) {
      setTimeout(() => {
        this.play();
      }, 500);
    }
    
    this.hasMoved = false;
  }
  
  showFrame(frameIndex) {
    // Ensure frame index is within bounds
    frameIndex = ((frameIndex % this.totalFrames) + this.totalFrames) % this.totalFrames;
    
    // Hide all frames
    this.frames.forEach((frame, index) => {
      if (index === frameIndex) {
        frame.classList.add('active');
      } else {
        frame.classList.remove('active');
      }
    });
    
    this.currentFrame = frameIndex;
    
    // Update scrubber position
    this.updateScrubberPosition();
  }
  
  updateScrubberPosition() {
    if (!this.scrubberThumb || !this.scrubberProgress) return;
    
    let percentage = (this.currentFrame / (this.totalFrames - 1)) * 100;
    
    if (this.isRTL) {
      // For RTL, position from right to left
      percentage = 100 - percentage;
      this.scrubberThumb.style.left = `${percentage}%`;
      this.scrubberProgress.style.right = '0';
      this.scrubberProgress.style.left = `${percentage}%`;
      this.scrubberProgress.style.width = `${100 - percentage}%`;
    } else {
      // For LTR, position from left to right
      this.scrubberThumb.style.left = `${percentage}%`;
      this.scrubberProgress.style.left = '0';
      this.scrubberProgress.style.right = 'auto';
      this.scrubberProgress.style.width = `${percentage}%`;
    }
  }
  
  goToFrame(frameIndex) {
    this.showFrame(frameIndex);
  }
  
  nextFrame(step = 1) {
    this.showFrame((this.currentFrame + step) % this.totalFrames);
  }
  
  prevFrame(step = 1) {
    this.showFrame((this.currentFrame - step + this.totalFrames) % this.totalFrames);
  }
  
  // Button click methods with animated step through intermediate frames
  nextFrameStep(wasPlaying = false) {
    if (this.isAnimatingStep) return; // Prevent multiple clicks during animation
    
    this.isAnimatingStep = true;
    const targetFrame = (this.currentFrame + this.buttonStepSize) % this.totalFrames;
    this.animateToFrame(targetFrame, 1, wasPlaying); // 1 = forward direction
  }
  
  prevFrameStep(wasPlaying = false) {
    if (this.isAnimatingStep) return; // Prevent multiple clicks during animation
    
    this.isAnimatingStep = true;
    const targetFrame = (this.currentFrame - this.buttonStepSize + this.totalFrames) % this.totalFrames;
    this.animateToFrame(targetFrame, -1, wasPlaying); // -1 = backward direction
  }
  
  animateToFrame(targetFrame, direction, shouldResumeAutoplay = false) {
    // Calculate how many steps we need to take
    let stepsRemaining = this.buttonStepSize;
    
    const step = () => {
      if (stepsRemaining > 0) {
        // Move one frame in the specified direction
        if (direction > 0) {
          this.showFrame((this.currentFrame + 1) % this.totalFrames);
        } else {
          this.showFrame((this.currentFrame - 1 + this.totalFrames) % this.totalFrames);
        }
        
        // Update scrubber position (already called by showFrame)
        // but we ensure it's visible during animation
        
        stepsRemaining--;
        
        // Schedule next step
        if (stepsRemaining > 0) {
          this.stepAnimationTimer = setTimeout(step, this.buttonStepSpeed);
        } else {
          // Animation complete
          this.isAnimatingStep = false;
          this.stepAnimationTimer = null;
          
          // Resume autoplay if it was playing before and autoplay is still enabled
          if (shouldResumeAutoplay && this.autoplayEnabled && this.isInViewport) {
            setTimeout(() => {
              this.play();
            }, 300); // Short delay before resuming autoplay from new frame
          }
        }
      }
    };
    
    // Start the animation
    step();
  }
  
  play() {
    if (this.isPlaying) return;
    
    // Don't play if images are still loading
    if (this.isLoading) {
      console.log('Cannot play: images still loading');
      return;
    }
    
    // Only play if element is in viewport (or viewport check is not initialized yet)
    if (this.observer && !this.isInViewport) return;
    
    this.isPlaying = true;
    this.classList.add('is-playing');
    this.classList.remove('is-paused');
    this.lastFrameTime = performance.now();
    this.animate();
  }
  
  pause() {
    // Stop animation if running
    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }
    
    this.isPlaying = false;
    this.classList.remove('is-playing');
    this.classList.add('is-paused');
  }
  
  togglePlayPause() {
    if (this.isPlaying) {
      this.pause();
      // Mark that user manually paused
      this.autoplayEnabled = false;
    } else {
      // Mark that user wants to play
      this.autoplayEnabled = true;
      
      // Only play if in viewport
      if (this.isInViewport || !this.observer) {
        this.play();
      }
    }
  }
  
  animate(currentTime) {
    if (!this.isPlaying) return;
    
    const elapsed = currentTime - this.lastFrameTime;
    
    if (elapsed >= this.autoplaySpeed) {
      // Reverse direction based on RTL mode
      if (this.isRTL) {
        this.nextFrame(); // In RTL, autoplay goes forward (visually right to left)
      } else {
        this.prevFrame(); // In LTR, autoplay goes backward (for standard rotation)
      }
      this.lastFrameTime = currentTime;
    }
    
    this.animationFrame = requestAnimationFrame(this.animate.bind(this));
  }
}

// Register custom element
if (!customElements.get('hdt-360-viewer')) {
  customElements.define('hdt-360-viewer', HDT360Viewer);
}