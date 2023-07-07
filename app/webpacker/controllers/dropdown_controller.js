import { Controller } from "stimulus";

export default class extends Controller {
  static targets = ["arrow", "menu"];

  connect() {
    this.collapsedClass = this.arrowTarget.dataset.collapsedClass.split(" ");
    this.expandedClass = this.arrowTarget.dataset.expandedClass.split(" ");
    this.#hide();
    document.addEventListener("click", this.#onBodyClick.bind(this));
  }

  disconnect() {
    document.removeEventListener("click", this.#onBodyClick);
  }

  toggle() {
    if (this.element.classList.contains("disabled")) {
      return;
    }
    if (this.menuTarget.classList.contains("hidden")) {
      this.#show();
    } else {
      this.#hide();
    }
  }

  #onBodyClick(event) {
    if (!this.element.contains(event.target)) {
      this.#hide();
    }
  }

  #show() {
    this.menuTarget.classList.remove("hidden");
    this.arrowTarget.classList.remove(...this.collapsedClass);
    this.arrowTarget.classList.add(...this.expandedClass);
  }
  #hide() {
    this.menuTarget.classList.add("hidden");
    this.arrowTarget.classList.remove(...this.expandedClass);
    this.arrowTarget.classList.add(...this.collapsedClass);
  }
}
