if (!customElements.get('read-more')) {
  customElements.define(
    'read-more',
    class ReadMore extends HTMLElement {
      constructor() {
        super();

        this.selectors = {
          content: '.read-more__content',
          button: '.read-more__toggle',
          buttonText: '.btn__text',
        };

        this.classes = {
          isDisabled: 'is-disabled',
          isCollapsed: 'is-collapsed',
        };

        this.toggleClass = this.dataset.toggleClass;
        this.showText = this.dataset.showText;
        this.hideText = this.dataset.hideText;
      }

      connectedCallback() {
        this.init();
      }

      init() {
        this.buttonEl = this.querySelector(this.selectors.button);
        this.contentEl = this.querySelector(this.selectors.content);

        if (!this.buttonEl || !this.contentEl) {
          return;
        }

        this.classList.remove(this.classes.isDisabled);
        this.contentEl.classList.remove(this.toggleClass);
        this.buttonEl.addEventListener('click', this.onClick.bind(this));
        this.contentEl.classList.add(this.toggleClass);
        this.classList.add(this.classes.isCollapsed);
      }

      showMore() {
        this.contentEl.classList.remove(this.toggleClass);
        this.classList.remove(this.classes.isCollapsed);
        const buttonTextEl = this.buttonEl.querySelector(this.selectors.buttonText);
        if (buttonTextEl) {
          buttonTextEl.textContent = this.hideText;
        }
      }

      showLess() {
        this.contentEl.classList.add(this.toggleClass);
        this.classList.add(this.classes.isCollapsed);
        const buttonTextEl = this.buttonEl.querySelector(this.selectors.buttonText);
        if (buttonTextEl) {
          buttonTextEl.textContent = this.showText;
        }
      }

      onClick(evt) {
        evt.preventDefault();
        if (this.contentEl.classList.contains(this.toggleClass)) {
          this.showMore();
        } else {
          this.showLess();
        }
      }
    }
  );
}
