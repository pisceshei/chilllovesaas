import { $4, $$4, $id4, debounce, formatMoney, fetchCache } from '@theme/utilities';
import { getterAdd, getterGet, getterRunFn, btnTooltip, DrawerComponent, VariantChangeBase } from "@theme/global";
import { ThemeEvents } from '@theme/events';
const { dialogClose, dialogOpen, cartCount, cartUpdate, currencyUpdate, cartReload, progressBarChange } = ThemeEvents;

// WISHLIST
var $wishlist_list = $id4('hdt_wishlist_list'),
  $compare_list = $id4('hdt_compare_list'),
  nameCachedWishlist = 'theme4:wishlist:id',
  nameCachedCompare = 'theme4:compare:id';
// if exit $wishlist_list is use app wishlist the4
if ($wishlist_list) {
  var arr_wishlist_list = $wishlist_list.textContent ? $wishlist_list.textContent.split(' ') : [];
}
else {
  var arr_wishlist_list = (!localStorage.getItem(nameCachedWishlist)) ? [] : localStorage.getItem(nameCachedWishlist).split(',');  // remove id: and conver array
}
if ($compare_list) {
  var arr_compare_list = $compare_list.textContent ? $compare_list.textContent.split(' ') : [];
}
else {
  var arr_compare_list = (!localStorage.getItem(nameCachedCompare)) ? [] : localStorage.getItem(nameCachedCompare).split(',');  // remove id: and conver array
}
// arr_wishlist_list = [1234, 5678, 9011]
// arr_compare_list = [1234, 5678, 9011]

var linkWishlistApp = '/apps/ecomrise/wishlist',
  linkCompareApp = '/apps/ecomrise/compare',
  actionAfterWishlistAdded = themeHDN.extras.AddedWishlistRemove ? 'remove' : 'added',
  actionAfterCompareAdded = themeHDN.extras.AddedCompareRemove ? 'remove' : 'added',
  limitWishlist = $wishlist_list ? 100 : 50,
  limitCompare = 5,
  conver_to_link_fn = function (prefix = this.textFn, array = this.array) {
    const x = themeHDN.routes.search_url + `/?view=${prefix}`,
      y = x + '&type=product&options[unavailable_products]=last&q=';
    return (array.length) ? y + encodeURI(`id:${array.join(' OR id:')}`) : x;
  };
// Reset if limit change
if (arr_wishlist_list.length > limitWishlist) {
  arr_wishlist_list.splice(limitWishlist - 1, arr_wishlist_list.length - 1);
  localStorage.setItem(nameCachedWishlist, arr_wishlist_list.toString());
}
// Check is page has item but not show reload page
if (window.isPageWishlist) {
  if (arr_wishlist_list.length && !window.isWishlistPerformed) {
    window.location.href = conver_to_link_fn('wishlist', arr_wishlist_list)
  } else {
    window.history.replaceState({}, document.title, conver_to_link_fn('wishlist', []));
  }
  themeHDN.wisHref = conver_to_link_fn('wishlist', arr_wishlist_list);
}

// Reset if limit change
if (arr_compare_list.length > limitCompare) {
  arr_compare_list.splice(limitCompare - 1, arr_compare_list.length - 1);
  localStorage.setItem(nameCachedCompare, arr_compare_list.toString());
}
// Check is page has item but not show reload page
if (window.isPageCompare) {
  if (arr_compare_list.length && !window.isComparePerformed) {
    window.location.href = conver_to_link_fn('compare', arr_compare_list)
  } else {
    window.history.replaceState({}, document.title, conver_to_link_fn('compare', []));
  }
}
var _wishlist_id, _wishlist_handle,
  _update_wis_text, update_wis_text_fn,
  _update_wis_btns, update_wis_btns_fn,
  _click_wis, click_wis_fn,
  _add_wis, add_wis_fn,
  _remove_wis, remove_wis_fn,
  _action_after_remove_add, action_after_remove_add_fn,
  _show_popup_compare, show_popup_compare_fn,
  _conver_to_link;
class Wishlist extends btnTooltip {
  constructor() {
    super();
    getterAdd(_wishlist_id, this, this.dataset.id);
    getterAdd(_wishlist_handle, this, this.dataset.handle);
    getterAdd(_update_wis_text, this);
    getterAdd(_update_wis_btns, this);
    getterAdd(_click_wis, this);
    getterAdd(_add_wis, this);
    getterAdd(_remove_wis, this);
    getterAdd(_action_after_remove_add, this);
    getterAdd(_show_popup_compare, this);
    getterAdd(_conver_to_link, this);
    this.tabIndex = 0;
    this.addEventListener("click", (event) => getterRunFn(_click_wis, this, click_wis_fn).call(this, event));
    this.addEventListener("keydown", (event) => {
      if (event.key == "Enter") getterRunFn(_click_wis, this, click_wis_fn).call(this, event)
    });
  }
  static get observedAttributes() {
    return ["action"];
  }
  get isFnWishlist() {
    return true;
  }
  get textFn() {
    return 'wishlist';
  }
  get isPageWishlistorCompare() {
    //add code check page
    return this.isFnWishlist ? window.isPageWishlist : window.isPageCompare;
  }
  get limit() {
    return this.isFnWishlist ? limitWishlist : limitCompare;
  }
  get nameCached() {
    return this.isFnWishlist ? nameCachedWishlist : nameCachedCompare;
  }
  get array() {
    return this.isFnWishlist ? arr_wishlist_list : arr_compare_list;
  }
  get actionAfterAdded() {
    return this.isFnWishlist ? actionAfterWishlistAdded : actionAfterCompareAdded;
  }
  get action() {
    return this.getAttribute('action');
  }
  attributeChangedCallback(name, oldValue, newValue) {
    if (oldValue === newValue || (oldValue === null && newValue === 'add')) return;
    getterRunFn(_update_wis_text, this, update_wis_text_fn).call(this, newValue);
    super.attributeChangedCallback(name, oldValue, newValue);
  }
  connectedCallback() {
    super.connectedCallback();
    if (this.array.indexOf(getterGet(_wishlist_id, this)) > -1) {
      if (this.hasAttribute('remove-on-page')) {
        return
      }
      this.setAttribute('action', this.actionAfterAdded);
    }
  }
};
_wishlist_id = new WeakMap();
_wishlist_handle = new WeakMap();
_update_wis_text = new WeakSet();
_update_wis_btns = new WeakSet();
_click_wis = new WeakSet();
_add_wis = new WeakSet();
_remove_wis = new WeakSet();
_action_after_remove_add = new WeakSet();
_conver_to_link = new WeakSet();
_show_popup_compare = new WeakSet();
update_wis_text_fn = function (value) {
  if (this.hasAttribute('remove-on-page')) return;
  const text = themeHDN.extras[`text_${this.isFnWishlist ? 'wis' : 'cp'}_${value}`],
    icon = themeHDN.extras[`icon_${this.isFnWishlist ? 'wis' : 'cp'}_${value}`];
  if (icon) this.firstElementChild.replaceWith(document.createRange().createContextualFragment(icon));
  if (text) {
    this.lastElementChild.textContent = text;
    this.setAttribute('data-txt-tt', text)
  }
};
update_wis_btns_fn = function (_action) {
  // Update Button
  $$4(`hdt-${this.textFn}[data-id="${getterGet(_wishlist_id, this)}"]`).forEach(btn => {
    btn.setAttribute('action', _action);
  });
  // Update Count and link
  document.dispatchEvent(new CustomEvent(`theme4:${this.textFn}:update`, {
    bubbles: true,
    detail: 'the4'  // arr_wishlist_list
  }));
  if ((window.isPageWishlist)) themeHDN.wisHref = conver_to_link_fn('wishlist', arr_wishlist_list);
};
click_wis_fn = function (e) {

  if (this.action == 'add') {
    // ADD
    getterRunFn(_add_wis, this, add_wis_fn).call(this);
  } else if (this.action === 'added') {
    // ADDED: go to page wishlist
    if (!this.isFnWishlist && themeHDN.extras.enableComparePopup) {
      getterRunFn(_show_popup_compare, this, show_popup_compare_fn).call(this);
    } else {
      window.location.href = getterRunFn(_conver_to_link, this, conver_to_link_fn).call(this);
    }
  } else {
    // REMOVE
    getterRunFn(_remove_wis, this, remove_wis_fn).call(this, e);
  }
};
add_wis_fn = function (e) {
  if ($wishlist_list && this.isFnWishlist || $compare_list && !this.isFnWishlist) {
    // app wishlist
    this.setAttribute('aria-busy', true);
    fetch(this.isFnWishlist ? linkWishlistApp : linkCompareApp, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        product_id: getterGet(_wishlist_id, this),
        product_handle: getterGet(_wishlist_handle, this),
        action: 'add'
      })
    })
      .then((response) => {
        return response.json()
      })
      .then((data) => {
        if (data.status != 'success') {
          console.error(data.message || 'Unknow error');
          return;
        }
        if (this.isFnWishlist) {
          arr_wishlist_list = JSON.parse(data.response.metafield.value).ecomrise_ids;
          if (!Array.isArray(arr_wishlist_list)) {
            arr_wishlist_list = arr_wishlist_list.split(',');
          }
        }
        if (!this.isFnWishlist) {
          arr_compare_list = JSON.parse(data.response.metafield.value).ecomrise_ids;
          if (!Array.isArray(arr_compare_list)) {
            arr_compare_list = arr_compare_list.split(',');
          }
          getterRunFn(_show_popup_compare, this, show_popup_compare_fn).call(this);
        }
        getterRunFn(_action_after_remove_add, this, action_after_remove_add_fn).call(this, this.actionAfterAdded);
      })
      .catch(function (error) {
        console.log('Error: ' + error);
      })
      .finally(() => {
        this.setAttribute('aria-busy', false);
      });
  }
  else {
    // local wishlist
    // adds the specified elements to the beginning of an array
    this.array.unshift(getterGet(_wishlist_id, this));
    //console.log(this.array, getterGet(_wishlist_id, this))
    if (this.array.length > this.limit) {
      // if over limit remove element on last array
      let arraySplice = this.array.splice(this.limit, 1);
      // arraySplice: allway has 1 element
      $$4(`hdt-${this.textFn}[data-id="${arraySplice[0]}"]`).forEach(btn => {
        btn.setAttribute('action', 'add');
      });
    }
    if (!this.isFnWishlist) getterRunFn(_show_popup_compare, this, show_popup_compare_fn).call(this);
    getterRunFn(_action_after_remove_add, this, action_after_remove_add_fn).call(this, this.actionAfterAdded);
    localStorage.setItem(this.nameCached, this.array.toString());
  }
};
remove_wis_fn = function (e) {
  e.preventDefault();
  e.stopPropagation();
  // REMOVE
  if ($wishlist_list && this.isFnWishlist || $compare_list && !this.isFnWishlist) {
    // app wishlist
    this.setAttribute('aria-busy', true);
    fetch(this.isFnWishlist ? linkWishlistApp : linkCompareApp, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        product_id: getterGet(_wishlist_id, this),
        product_handle: getterGet(_wishlist_handle, this),
        action: 'add',
        _method: 'DELETE'
      })
    })
      .then((response) => {
        return response.json()
      })
      .then((data) => {
        if (data.status != 'success') {
          console.error(data.message || 'Unknow error');
          return;
        }
        arr_wishlist_list = JSON.parse(data.response.metafield.value).ecomrise_ids;
        if (!Array.isArray(arr_wishlist_list)) {
          arr_wishlist_list = arr_wishlist_list.split(',');
        }
        getterRunFn(_action_after_remove_add, this, action_after_remove_add_fn).call(this, 'add');
      })
      .catch(function (error) {
        console.log('Error: ' + error);
      })
      .finally(() => {
        this.setAttribute('aria-busy', false);
      });
  } else {
    // local wishlist
    this.array.splice(this.array.indexOf(getterGet(_wishlist_id, this)), 1);
    localStorage.setItem(this.nameCached, this.array.toString());

    getterRunFn(_action_after_remove_add, this, action_after_remove_add_fn).call(this, 'add');
  }
};
action_after_remove_add_fn = function (action) {

  if (this.getAttribute('action') == 'remove' && this.hasAttribute('remove-on-page')) {
    if (this.isFnWishlist) {
      this.setAttribute('aria-busy', true);
      if (this.isPageWishlistorCompare) window.location.href = getterRunFn(_conver_to_link, this, conver_to_link_fn).call(this);
      // this.closest('.hdt-card-product').remove();
    } else {
      $$4(`.hdt-compare-item-${getterGet(_wishlist_id, this)}`).forEach(item => {
        item.remove();
        // console.log("Remove compare item");
      });
    }
    getterRunFn(_update_wis_btns, this, update_wis_btns_fn).call(this, action);
    if (this.array.length == 0) {
      $id4('drawerCompare')?.closest('hdt-drawer')?.close();
      if (this.isPageWishlistorCompare) window.location.href = getterRunFn(_conver_to_link, this, conver_to_link_fn).call(this);
    }
    //this.setAttribute('action', action);
  } else {
    getterRunFn(_update_wis_btns, this, update_wis_btns_fn).call(this, action);
    // is page wishlist or compare reload page
    if (this.isPageWishlistorCompare) window.location.href = getterRunFn(_conver_to_link, this, conver_to_link_fn).call(this);
  }
};
show_popup_compare_fn = function (event) {
  if (!themeHDN.extras.enableComparePopup || this.isPageWishlistorCompare) return;
  // add code if want show popup compare
  $id4('drawerCompare')?.closest('hdt-drawer')?.open();
  fetch(conver_to_link_fn('compare', arr_compare_list) + "&section_id=compare-offcanvas")
    .then((response) => response.text())
    .then((text) => {
      const html = document.createElement('div');
      html.innerHTML = text;
      const prds = html.querySelector('offcanvas-compare');

      if (prds && prds.innerHTML.trim().length) {

        $4("offcanvas-compare").innerHTML = prds.innerHTML;
      }
    })
    .catch((e) => {
      console.error(e);
    });
};
var _clear_all, clear_all_fn;
class ClearAll extends HTMLElement {
  constructor() {
    super();
    getterAdd(_clear_all, this);
    this.tabIndex = 0;
    this.addEventListener("click", getterRunFn(_clear_all, this, clear_all_fn));
    this.addEventListener("keydown", (event) => {
      if (event.key == "Enter") getterRunFn(_clear_all, this, clear_all_fn).call(this)
    });
  }
  get ofFn() {
    return this.getAttribute('of-fn'); //'compare', 'wishlist'
  }
  get nameCached() {
    return this.ofFn == 'compare' ? nameCachedCompare : nameCachedWishlist;
  }
  set array(value) {
    this.ofFn == 'compare' ? arr_compare_list = value : arr_wishlist_list = value;
  }
};
_clear_all = new WeakSet();
clear_all_fn = function () {
  localStorage.removeItem(this.nameCached);
  // Update Buttons
  $$4(`hdt-${this.ofFn}[action="added"]`).forEach(btn => {
    btn.setAttribute('action', 'add');
  });
  // Update Count and link
  document.dispatchEvent(new CustomEvent(`theme4:${this.ofFn}:update`, {
    bubbles: true,
    detail: 'the4'
  }));
  this.array = [];
  $id4(`drawerCompare`)?.closest('hdt-drawer')?.close();
  if ($4(`#drawerCompare offcanvas-compare`)) {
    $4(`#drawerCompare offcanvas-compare`).innerHTML = "";
  }
};
customElements.define("hdt-clear-all", ClearAll);
// eg: <hdt-clear-all role="button" of-fn="compare">Clear All </hdt-clear-all>

// Update count
class WishlistCount extends HTMLElement {
  constructor() {
    super();
    this.textContent = this.array.length;
    document.addEventListener(`theme4:${this.prefix}:update`, (e) => {
      //console.log(this.prefix + ' count update.');
      this.textContent = this.array.length;
    });
  }
  get isFnWishlist() {
    return true;
  }
  get array() {
    return this.isFnWishlist ? arr_wishlist_list : arr_compare_list;
  }
  get prefix() {
    return this.isFnWishlist ? 'wishlist' : 'compare';
  }
}
// Update link page
class WishlistLink extends HTMLElement {
  constructor() {
    super();
    $4('a', this).href = conver_to_link_fn(this.prefix, this.array);
    //console.log('WishlistLink', this.href)
    document.addEventListener(`theme4:${this.prefix}:update`, (e) => {
      $4('a', this).href = conver_to_link_fn(this.prefix, this.array);
    });
  }
  get isFnWishlist() {
    return true;
  }
  get array() {
    return this.isFnWishlist ? arr_wishlist_list : arr_compare_list;
  }
  get prefix() {
    return this.isFnWishlist ? 'wishlist' : 'compare';
  }
}
customElements.define("hdt-wishlist", Wishlist);
customElements.define("hdt-wishlist-count", WishlistCount);
customElements.define("hdt-wishlist-a", WishlistLink);

// COMPARE
class Compare extends Wishlist {
  get isFnWishlist() {
    return false;
  }
  get textFn() {
    return 'compare';
  }
}
// Update count
class CompareCount extends WishlistCount {
  get isFnWishlist() {
    return false;
  }
}
// Update link page
class CompareLink extends WishlistLink {
  get isFnWishlist() {
    return false;
  }
}
customElements.define("hdt-compare", Compare);
customElements.define("hdt-compare-count", CompareCount);
customElements.define("hdt-compare-a", CompareLink);

// footer accodion
function handleAccordionClick() {
  let accordion = this.parentElement;
  accordion.classList.toggle('open');
  if (window.innerWidth < 768) {
    let content = accordion.querySelector('.hdt-collapse-content');
    if (accordion.classList.contains('open')) {
      content.style.height = content.scrollHeight + 'px';
    } else {
      content.style.height = '0';
    }
  }
}
function updateMaxHeight() {
  if (window.innerWidth >= 768) {
    document.querySelectorAll('.hdt-footer-section .hdt-collapse-content').forEach(function (content) {
      content.style.height = '';
    });
  }
}
document.querySelectorAll('.hdt-footer-section .hdt-footer-heading').forEach(function (element) {

  element.addEventListener('click', handleAccordionClick);
});
window.addEventListener('resize', function () {
  if (window.innerWidth < 768) {
    document.querySelectorAll('.hdt-footer-section .hdt-footer-heading').forEach(function (element) {
      element.removeEventListener('click', handleAccordionClick);
      element.addEventListener('click', handleAccordionClick);
    });
  } else {
    document.querySelectorAll('.hdt-footer-section .hdt-footer-heading').forEach(function (element) {
      element.removeEventListener('click', handleAccordionClick);
    });
    updateMaxHeight();
  }
});


// --------------------------
// Back to top
// --------------------------
class BackToTop extends HTMLElement {
  constructor() {
    super();
    this.config = JSON.parse(this.getAttribute('config'));
    if (window.innerWidth < 768 && this.config.hiddenMobile) return;
    this.debounce_timer = 0;
    this.debounce_timer2 = 0;
    this.circlechart = this.querySelector('.hdt-circle-css');
    this.addEventListener("click", this.goTop.bind(this));
    window.addEventListener("scroll", this.backToTop.bind(this));
  }
  goTop() {
    document.body.scrollTop = 0; // For Safari
    document.documentElement.scrollTop = 0; // For Chrome, Firefox, IE and Opera
  }

  backToTop() {
    let self = this;
    if (this.debounce_timer) { clearTimeout(this.debounce_timer); }
    this.debounce_timer = setTimeout(function () {
      if (window.scrollY > self.config.scrollTop) {
        self.classList.add('is--show');
      } else {
        self.classList.remove('is--show');
      }
    }, 40);

    if (!this.circlechart) return;

    if (this.debounce_timer2) { clearTimeout(this.debounce_timer2); }

    this.debounce_timer2 = setTimeout(function () {
      let scrollTop2 = window.scrollY,
        docHeight = document.body.offsetHeight,
        winHeight = window.innerHeight,
        scrollPercent = scrollTop2 / (docHeight - winHeight),
        degrees = scrollPercent * 360;
      self.circlechart.style.setProperty("--cricle-degrees", degrees + 'deg');
    }, 6);
  }
}

customElements.define('back-to-top', BackToTop);

// --------------------------
// Form status
// --------------------------


const contactForm = $$4('form[action^="/contact"]');
contactForm.forEach(function (form) {
  form.addEventListener("submit", function (event) {
    sessionStorage.setItem("the4:recentform", this.getAttribute("id"));
  })
});
var recentform = sessionStorage.getItem("the4:recentform") || "";

if (location.href.indexOf('contact_posted=true') > 0 && recentform !== "") {
  document.dispatchEvent(new CustomEvent('the4:recentform', { detail: { recentform: recentform }, bubbles: true, cancelable: true }));
  $id4(recentform)?.classList.add("on-live");
  if (recentform.indexOf('ContactFormAsk') >= 0 && $id4(recentform).length > 0) {
    let modal_id = document.getElementById(recentform).getAttribute('data-modal');
    document.getElementById(modal_id).closest('hdt-modal').open();
    sessionStorage.removeItem("the4:recentform");
  }
  if ($4('.form-status-mirror-' + recentform)) {
    $4('.form-status-mirror-' + recentform).style.cssText = "display: block;";
  }
}

else if (location.href.indexOf('customer_posted=true') > 0 && recentform !== "") {
  document.addEventListener('the4:recentform', (event) => {
    let modal_id = document.getElementById(event.detail.recentform).getAttribute('data-id');
    document.getElementById(modal_id).closest('hdt-modal').open();
  })
  document.dispatchEvent(new CustomEvent('the4:recentform', { detail: { recentform: recentform }, bubbles: true, cancelable: true }));
  $id4(recentform)?.classList.add("on-live");
}
else if (location.href.indexOf('contact_posted=true') > 0 && location.href.indexOf('#') > 0) {
  var recentform = location.href.split("#")[1];
  if ($id4(recentform).length > 0) {
    sessionStorage.setItem("the4:recentform", recentform);
    $id4(recentform).classList.add("on-live");
    if ($4('.form-status-mirror-' + recentform)) {
      $4('.form-status-mirror-' + recentform).style.cssText = "display: block;";
    }
  }
}

// --------------------------
// numberRandom
// --------------------------
class numberRandom extends HTMLElement {
  constructor() {
    super();
    let config = JSON.parse(this.getAttribute("config"));
    this.min = config.min;
    this.max = config.max;
    this.interval = config.interval;
    this.number = Math.floor(Math.random() * (this.max - this.min + 1)) + this.min;
    this.ofset = ["1", "2", "4", "3", "6", "10", "-1", "-3", "-2", "-4", "-6"];
    this.prioritize = ["10", "20", "15"];
    this.h = "";
    this.e = "";
    this.M = "";
    this.liveViewInt();
    setInterval(this.liveViewInt.bind(this), this.interval);
  }

  liveViewInt() {
    if (this.h = Math.floor(Math.random() * this.ofset.length), this.e = this.ofset[this.h], this.number = parseInt(this.number) + parseInt(this.e), this.min >= this.number) {
      this.M = Math.floor(Math.random() * this.prioritize.length);
      var a = this.prioritize[this.M];
      this.number += a
    }
    if (this.number < this.min || this.number > this.max) {
      this.number = Math.floor(Math.random() * (this.max - this.min + 1)) + this.min;
    }
    this.innerHTML = parseInt(this.number);
  }
}

customElements.define('number-random', numberRandom);

// --------------------------
// Total sold flash
// --------------------------
class flashSold extends VariantChangeBase {
  constructor() {
    super();
    var self = this;
    this.time = this.getAttribute("time");
    this.config = JSON.parse(this.getAttribute("flash-sold"));
    this.mins = this.config.mins;
    this.maxs = this.config.maxs;
    this.mint = this.config.mint;
    this.maxt = this.config.maxt;
    this.dataID = this.config.id;
    this.getS = sessionStorage.getItem("soldS" + this.dataID) || this.getRandomInt(this.mins, this.maxs);
    this.getT = sessionStorage.getItem("soldT" + this.dataID) || this.getRandomInt(this.mint, this.maxt);
    this.numS = parseInt(this.getS);
    this.numT = parseInt(this.getT);
    this.intervalTime = parseInt(this.config.time);
    this.$sold = this.querySelector('[data-sold]');
    this.$hour = this.querySelector('[data-hour]');
    this.limitMinMax();
    this.updateSold(this.numS, this.numT);
    setInterval(function () {
      this.numS = this.numS + self.getRandomInt(1, 4);
      this.numT = this.numT + (Math.random() * (0.8 - 0.1) + 0.1).toFixed(1) * 1;
      self.limitMinMax();
      self.updateSold(self.numS, self.numT);
    }, this.intervalTime);
  }

  getRandomInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  updateSold(num1, num2) {
    this.$sold.innerHTML = num1;
    this.$hour.innerHTML = Math.floor(this.numT);
    sessionStorage.setItem("soldS" + this.dataID, num1);
    sessionStorage.setItem("soldT" + this.dataID, num2);
  }
  limitMinMax() {
    if (this.numS > this.maxs) this.numS = self.getRandomInt(this.mins, this.maxs)
    if (this.numT > this.maxt) this.numT = self.getRandomInt(this.mins, this.maxt)
  }
  #preVariantId;
  onVariantChanged(event) {
    const variant = event.detail.variant;
    if (variant && this.#preVariantId != variant.id) {
      if (variant.available) {
        this.closest(".hdt-product-info__item").style.display = "block"
      }
      else {
        this.closest(".hdt-product-info__item").style.display = "none"
      }
    }
  }
}
customElements.define('flash-sold', flashSold);

// ======================================
//    pages/brands -  filter isotope 
// ======================================
class filterIsotope extends HTMLElement {
  constructor() {
    super();
    this.btns = this.querySelectorAll('button');
    this.id = this.id;
    if (!this.btns) {
      return;
    }
    this.handleButtonClick();
  }
  handleButtonClick() {
    this.btns.forEach(btn => {
      btn.addEventListener('click', () => {
        this.querySelector('button.active').classList.remove('active');
        btn.classList.add('active');

        let selectedFilter = btn.getAttribute('data-filter');
        let itemsToHide = $$4(`#${this.id} .hdt-brand-item:not(${selectedFilter})`);
        let itemsToShow = $$4(`#${this.id} ${selectedFilter}`);

        if (selectedFilter == '._filter-show-all') {
          itemsToHide = [];
          itemsToShow = $$4(`#${this.id} .hdt-brand-item`);
        }

        itemsToShow.forEach(el => {
          el.classList.remove('animate-filter-hide', 'hdt-hidden');
          el.classList.add('animate-filter-show');
        });

        itemsToHide.forEach(el => {
          el.classList.add('animate-filter-hide', 'hdt-hidden');
          el.classList.remove('animate-filter-show');
        });
      })
    })
  }
}
customElements.define('hdt-brands', filterIsotope);

// ======================================
//   countryFilter 
// ======================================
class countryFilter extends HTMLElement {
  constructor() {
    super();
    this.search = $4('[name=country_filter]', this);
    this.reset = $4(".hdt-country_filter__reset", this);
    if (this.search) {
      this.search.addEventListener(
        'input',
        debounce((event) => {
          this.filterCountries();
        }, 200).bind(this)
      );
    }
    this.search.addEventListener('keydown', this.onSearchKeyDown.bind(this));

  }
  filterCountries() {
    const searchValue = this.search.value.toLowerCase();
    const allCountries = this.closest("hdt-popover").querySelectorAll('hdt-richlist button');
    let visibleCountries = allCountries.length;
    allCountries.forEach((item) => {
      const countryName = item.getAttribute('data-name').toLowerCase();
      if (countryName.indexOf(searchValue) > -1) {
        item.classList.remove('hdt-d-none');
        visibleCountries++;
      } else {
        item.classList.add('hdt-d-none');
        visibleCountries--;
      }
    });
    if (window.innerWidth > 768) this.closest("hdt-popover").updatePos();
    this.closest("hdt-popover").querySelector('.hdt-current-scrollbar').scrollTop = 0;
  }

  onSearchKeyDown(event) {
    if (event.code.toUpperCase() === 'ENTER') {
      event.preventDefault();
    }
  }
}

customElements.define('country-filter', countryFilter);



// --------------------------
// Product Recommendations
// --------------------------
class ProductRecommendations extends HTMLElement {
  constructor() {
    super();
  }

  get fetchType() {
    return parseInt(this.getAttribute('data-fetch-type')) || 1;
  }
  connectedCallback() {
    if (this.hasAttribute('no-observe') || this.fetchType === 2 || this.fetchType === 3) {
      this.fetchAction();
      return;
    }
    const handleIntersection = (entries, observer) => {
      if (!entries[0].isIntersecting) return;
      observer.unobserve(this);
      this.fetchAction();
    };
    new IntersectionObserver(handleIntersection.bind(this), { rootMargin: '0px 0px 400px 0px' }).observe(this);
  }

  async fetchAction() {
    // fetch(this.dataset.url)
    //   .then((response) => response.text())
    //   .then((text) => {
    //     const html = document.createElement('div');
    //     html.innerHTML = text;
    //     const recommendations = html.querySelector('product-recommendations');

    //     if (recommendations && recommendations.innerHTML.trim().length) {
    //       this.innerHTML = recommendations.innerHTML;
    //     }
    //     document.dispatchEvent(new CustomEvent("currency:update"));
    //   })
    //   .catch((e) => {
    //     console.error(e);
    //   });
    try {
      const responseData = await (await fetchCache(this.dataset.url)).text();
      const html = document.createElement('div');
      html.innerHTML = responseData;
      const sectionId = this.dataset.sectionId;
      const recommendations = html.querySelector(`product-recommendations[data-section-id="${sectionId}"]`);
      if (recommendations && recommendations.innerHTML.trim().length) {
        this.innerHTML = recommendations.innerHTML;
      }
      document.dispatchEvent(new CustomEvent("currency:update"));
    } catch (error) {
      console.error(error);
    }
  }
}

customElements.define('product-recommendations', ProductRecommendations);

// --------------------------
// Product Recently
// --------------------------
class ProductRecently extends HTMLElement {
  constructor() {
    super();
  }

  connectedCallback() {
    const handleIntersection = (entries, observer) => {
      if (!entries[0].isIntersecting) return;
      observer.unobserve(this);
      let handleProducts = localStorage.getItem("theme4:recently:id");
      let prdId = this.dataset.id;
      let limit = parseInt(this.dataset.limit);
      if (handleProducts !== null) {
        let products = handleProducts.split(',');
        if (this.dataset.reverse === 'true') {
          products = products.reverse();
        }
        if (prdId == products[0] && products.length == 1) {
          this.closest('.section').style.display = 'none';
          return;
        }
        let url = this.dataset.url.replace('q=', 'q=id:' + products.join("%20OR%20id:"));
        fetch(url)
          .then((response) => response.text())
          .then((text) => {
            const html = document.createElement('div');
            html.innerHTML = text.replace('hdt-slider-wait', 'hdt-slider');
            const recently = html.querySelector('product-recently');

            if (recently && recently.innerHTML.trim().length) {
              this.innerHTML = recently.innerHTML;
              // html.innerHTML = text.replace('hdt-slider-wait', 'hdt-slider');
            }
            document.dispatchEvent(new CustomEvent("currency:update"));
          })
          .catch((e) => {
            console.error(e);
          });

      }
      let arrayProducts = handleProducts !== null ? handleProducts.split(',') : new Array;
      if (arrayProducts.length == 0) {
        this.closest('.shopify-section').style.display = 'none';
      }
      if (!arrayProducts.includes(prdId + '')) {
        if (arrayProducts.length >= limit) {
          arrayProducts.pop();
        }
        function prepend(value, array) {
          var newArray = array.slice();
          newArray.unshift(value);
          return newArray;
        }
        arrayProducts = prepend(prdId, arrayProducts);
        arrayProducts = arrayProducts.toString();
        localStorage.setItem("theme4:recently:id", arrayProducts);
      } else {
        const prdIdStr = prdId + '';
        const index = arrayProducts.indexOf(prdIdStr);
        if (index > -1) {
          arrayProducts.splice(index, 1);
          arrayProducts.unshift(prdIdStr);
          arrayProducts = arrayProducts.toString();
          localStorage.setItem("theme4:recently:id", arrayProducts);
        }
      }
    };

    new IntersectionObserver(handleIntersection.bind(this), { rootMargin: '0px 0px 400px 0px' }).observe(this);
  }
}

customElements.define('product-recently', ProductRecently);


// --------------------------
// Product Ask Question
// --------------------------

const modalAsk = document.getElementById('modal-contactFormAsk');
modalAsk.addEventListener('dialog:opening', function (event) {
  let askBtn = modalAsk.closest('hdt-modal').dialog.btnOpening;
  let product = askBtn.getAttribute('data-product');
  let product_info = askBtn.parentElement.querySelector('.hdt-pr-popup__ask-product');
  if (product_info) {
    const modalHeader = modalAsk.querySelector('.hdt-dialog-modal__header');
    if (modalHeader && product_info) {
      const oldProductInfo = modalHeader.querySelector('.hdt-pr-popup__ask-product');
      if (oldProductInfo) {
        oldProductInfo.remove();
      }
      modalHeader.prepend(product_info.cloneNode(true));
    }
  }
  let productAsk = modalAsk.querySelector('[name="contact[product]"]');
  if (productAsk) {
    let currentValue = productAsk.value || '';
    let newValue = product || '';

    if (currentValue !== newValue) {
      let formMessage = modalAsk.querySelector('.hdt-form-message');
      if (formMessage) {
        formMessage.remove();
      }
    }
    if (currentValue !== newValue || currentValue === '') {
      productAsk.value = newValue;
    }
  }
})

// --------------------------
// Predictive Search
// --------------------------
class PredictiveSearch extends DrawerComponent {
  constructor() {
    super();
    // console.log(!this.hasAttribute('enabled'))
    // if (!this.hasAttribute('enabled')) return;
    this.action = themeHDN.routes.predictive_search_url;
    if (!this.hasAttribute('enabled') || this.isArabic) {
      this.action = themeHDN.routes.search_url;
    };
    this.cachedResults = {};
    this.predictiveSearchResults = $4('[data-results-search]', this);
    this.select = $4('[data-cat-search]>select', this);
    this.input = $4('input[type="search"]', this);
    this.sectionIdResults = this.getAttribute('data-section-id-results') || 'hdt_predictive-search';
    this.allPredictiveSearchInstances = $$4('predictive-search');
    this.skeleton = $4('[data-skeleton-search]', this);
    this.noResults = $4('.hdt-cart-no-results', this);
    this.hideWrapper = $4('.hdt-cart-hide-has-results', this);
    this.showWrapper = $4('.hdt-cart-show-has-results', this);
    this.btn_viewall = $4('.hdt-view_all', this);
    this.href = this.btn_viewall?.getAttribute("href");
    this.btn_viewall_replace_text = $4('[data-replace-text]', this);
    this.isOpen = false;
    this.abortController2 = new AbortController();
    this.searchTerm = '';

    if (this.input) {
      this.input.addEventListener(
        'input',
        debounce((event) => {
          this.onChange(event);
        }, 300).bind(this)
      );
    }
    if (this.select) {
      this.select.addEventListener(
        'change',
        debounce((event) => {
          this.onChange(event);
        }, 300).bind(this)
      );
    }

    const formData = new FormData(this.input.form);
    this.params = "";
    for (const [key, value] of formData) {
      if (key === 'q') break;
      this.params += `${key}=${value}&`;
    }

    this.setupEventListeners();
  }

  get isArabic(){
    return document.querySelector('html').getAttribute('dir') === 'rtl';
  }

  setupEventListeners() {
    this.input.form.addEventListener('submit', this.onFormSubmit.bind(this));

    this.input.addEventListener('focus', this.onFocus.bind(this));
    this.addEventListener('focusout', this.onFocusOut.bind(this));
    this.addEventListener('keyup', this.onKeyup.bind(this));
    //this.addEventListener('keydown', this.onKeydown.bind(this));
  }

  getQuery() {
    var currentValue = this.input.value.trim();
    if (this.select) {
      this.selectVal = this.select.value || '*';
      var valSelected = this.selectVal.trim();
      //console.log(valSelected)
      if (valSelected != '*') {
        if (currentValue !== '') {
          currentValue = `product_type:${valSelected} AND ${currentValue}`;
        } else {
          currentValue = `product_type:${valSelected}`;
        }
      }
    }

    return currentValue;
  }

  onChange() {
    const newSearchTerm = this.getQuery();
    // console.log(newSearchTerm)
    if (!this.searchTerm || !newSearchTerm.startsWith(this.searchTerm)) {
      // Remove the results when they are no longer relevant for the new search term
      // so they don't show up when the dropdown opens again
      // this.querySelector('#predictive-search-results-groups-wrapper')?.remove();
    }

    // Update the term asap, don't wait for the predictive search query to finish loading
    this.updateSearchForTerm(this.searchTerm, newSearchTerm);

    this.searchTerm = newSearchTerm;
    this.btn_viewall?.setAttribute("href", this.href.replace(/\/search\?q=.*/g, "/search?q=" + this.searchTerm));
    this.btn_viewall_replace_text ? this.btn_viewall_replace_text.innerText = themeHDN.extras.search.view_all + ` ${this.searchTerm}` : null;

    if (!this.searchTerm.length) {
      this.close(true);
      return;
    }
    this.getSearchResults(this.searchTerm);
  }

  onFormSubmit(event) {
    if (!this.getQuery().length || this.querySelector('[aria-selected="true"] a')) event.preventDefault();
  }

  onFocus() {
    const currentSearchTerm = this.getQuery();
    if (!currentSearchTerm.length) return;
    if (this.searchTerm !== currentSearchTerm) {
      // Search term was changed from other search input, treat it as a user change
      this.onChange();
    } else if (this.getAttribute('results') === 'true') {
      this.openSearch();
    } else {
      this.getSearchResults(this.searchTerm);
    }
  }

  onFocusOut() {
    setTimeout(() => {
      if (!this.contains(document.activeElement)) this.close();
    });
  }

  onKeyup(event) {
    if (!this.getQuery().length) this.close(true);
    event.preventDefault();

    // switch (event.code) {
    //   case 'ArrowUp':
    //     this.switchOption('up');
    //     break;
    //   case 'ArrowDown':
    //     this.switchOption('down');
    //     break;
    //   case 'Enter':
    //     this.selectOption();
    //     break;
    // }
  }

  // onKeydown(event) {
  //   // Prevent the cursor from moving in the input when using the up and down arrow keys
  //   if (event.code === 'ArrowUp' || event.code === 'ArrowDown') {
  //     event.preventDefault();
  //   }
  // }
  updateSearchForTerm(previousTerm, newTerm) {
    const searchForTextElement = this.querySelector('[data-predictive-search-search-for-text]');
    const currentButtonText = searchForTextElement?.innerText;
    if (currentButtonText) {
      if (currentButtonText.match(new RegExp(previousTerm, 'g')).length > 1) {
        // The new term matches part of the button text and not just the search term, do not replace to avoid mistakes
        return;
      }
      const newButtonText = currentButtonText.replace(previousTerm, newTerm);
      searchForTextElement.innerText = newButtonText;
    }
  }

  getSearchResults(searchTerm) {
    const queryKey = searchTerm.replace(' ', '-').toLowerCase();
    this.setLiveRegionLoadingState();

    if (this.cachedResults[queryKey]) {
      this.renderSearchResults(this.cachedResults[queryKey]);
      return;
    }

    fetch(`${this.action}?q=${encodeURIComponent(searchTerm)}&${this.params}section_id=${this.sectionIdResults}`, {
      signal: this.abortController2.signal,
    })
      .then((response) => {
        if (!response.ok) {
          var error = new Error(response.status);
          this.close();
          throw error;
        }

        return response.text();
      })
      .then((text) => {
        const resultsMarkup = new DOMParser()
          .parseFromString(text, 'text/html')
          .querySelector('#shopify-section-' + this.sectionIdResults).innerHTML;
        // Save bandwidth keeping the cache in all instances synced
        this.allPredictiveSearchInstances.forEach((predictiveSearchInstance) => {
          this.cachedResults[queryKey] = resultsMarkup;
        });
        this.renderSearchResults(resultsMarkup);
      })
      .catch((error) => {
        if (error?.code === 20) {
          // Code 20 means the call was aborted
          return;
        }
        this.close();
        throw error;
      });
  }

  setLiveRegionLoadingState() {
    this.hideWrapper.style.cssText = "display: none;";
    this.showWrapper.style.cssText = "display: block;";
    this.skeleton.classList.remove("hdt-hidden");

    this.setAttribute('loading', true);
  }

  renderSearchResults(resultsMarkup) {
    this.predictiveSearchResults.innerHTML = resultsMarkup;
    this.setAttribute('results', true);

    this.setLiveRegionResults();
    this.openSearch();
    document.dispatchEvent(new CustomEvent("currency:update"));
  }

  setLiveRegionResults() {
    this.removeAttribute('loading');
  }

  openSearch() {
    //this.setAttribute('open', true);
    this.input.setAttribute('aria-expanded', true);
    this.skeleton.classList.add("hdt-hidden");
    this.isOpen = true;
  }

  close(clearSearchTerm = false) {
    this.closeResults(clearSearchTerm);
    this.isOpen = false;
  }

  closeResults(clearSearchTerm = false) {
    if (clearSearchTerm) {
      this.input.value = '';
      this.removeAttribute('results');
      this.hideWrapper.style.cssText = "display: block;";
      this.showWrapper.style.cssText = "display: none;";
      this.predictiveSearchResults.innerHTML = "";
    }
    const selected = this.querySelector('[aria-selected="true"]');

    if (selected) selected.setAttribute('aria-selected', false);

    this.input.setAttribute('aria-activedescendant', '');
    this.removeAttribute('loading');
    //this.removeAttribute('open');
    this.input.setAttribute('aria-expanded', false);
    this.resultsMaxHeight = false;
    this.predictiveSearchResults.removeAttribute('style');
  }
}

customElements.define('hdt-predictive-search', PredictiveSearch);

// --------------------------
// Delivery Time
// --------------------------
// https://unpkg.com/dayjs@1.11.10/dayjs.min.js
import dayjs from "@theme/dayjs";
dayjs.locale('en'); // use locale globally
class orderDelivery extends VariantChangeBase {
  constructor() {
    super();
    this.config = JSON.parse(this.getAttribute('config'));
    this.offDays = this.config.off_day.replace(/ /g, '').split(",");
    this.nowDay = dayjs();
    var format_day = this.config.format_day,
      time = this.config.time.replace("24:00:00", "23:59:59"),
      arrDayWeek = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"],
      dateStart = this.config.estimateStartDate || 0,
      dateEnd = this.config.estimateEndDate || 0,
      excludeDays = this.config.cut_day.replace(/ /g, '').split(","),
      startDay = dayjs(),
      i = 0,
      endDay = dayjs(),
      j = 0,
      nowTime = this.nowDay.format('HHmmss'),
      timeint = time.replace(/ /g, '').replace(/:/g, ''),

      arrDay = themeHDN.extras.order.dayNames.replace(/ /g, '').split(","),
      arrMth = themeHDN.extras.order.monthNames.replace(/ /g, '').split(",");
    /**
     * Check Time, if nowTime >=  timeint +1 day
     */
    if (parseInt(nowTime) >= parseInt(timeint)) {
      this.nowDay = this.nowDay.add(1, 'day');
      startDay = startDay.add(1, 'day');
      endDay = endDay.add(1, 'day');
    }

    /**
     * Mode: 2 - Shipping + delivery
     * Mode: 1 - Only delivery
     */

    if (this.config.mode == '2') {

      // START DATE
      // if ngay khach mua trung voi ngay loai tru tang 1 ngay
      while (excludeDays.indexOf(arrDayWeek[startDay.format('d')]) > -1 || this.offDays.indexOf(startDay.format('DD/MM/****')) > -1 || this.offDays.indexOf(startDay.format('DD/MM/YYYY')) > -1) {
        startDay = startDay.add(1, 'day');
      }
      while (i < dateStart) {
        i++;
        startDay = startDay.add(1, 'day');
        if (excludeDays.indexOf(arrDayWeek[startDay.format('d')]) > -1 || this.offDays.indexOf(startDay.format('DD/MM/****')) > -1 || this.offDays.indexOf(startDay.format('DD/MM/YYYY')) > -1) {
          i--;
        }
      }

      // END DATE
      // if ngay khach mua trung voi ngay loai tru tang 1 ngay
      while (excludeDays.indexOf(arrDayWeek[endDay.format('d')]) > -1 || this.offDays.indexOf(endDay.format('DD/MM/****')) > -1 || this.offDays.indexOf(endDay.format('DD/MM/YYYY')) > -1) {
        endDay = endDay.add(1, 'day');
      }

      while (j < dateEnd) {
        j++;
        endDay = endDay.add(1, 'day');
        if (excludeDays.indexOf(arrDayWeek[endDay.format('d')]) > -1 || this.offDays.indexOf(endDay.format('DD/MM/****')) > -1 || this.offDays.indexOf(endDay.format('DD/MM/YYYY')) > -1) {
          j--;
        }
      }

    }
    else {

      // START DATE
      startDay = startDay.add(dateStart, 'day');
      while (excludeDays.indexOf(arrDayWeek[startDay.format('d')]) > -1 || this.offDays.indexOf(startDay.format('DD/MM/****')) > -1 || this.offDays.indexOf(startDay.format('DD/MM/YYYY')) > -1) {
        startDay = startDay.add(1, 'day');
      }

      // END DATE
      endDay = endDay.add(dateEnd, 'day');
      while (excludeDays.indexOf(arrDayWeek[endDay.format('d')]) > -1 || this.offDays.indexOf(endDay.format('DD/MM/****')) > -1 || this.offDays.indexOf(endDay.format('DD/MM/YYYY')) > -1) {
        endDay = endDay.add(1, 'day');
      }
      // endDay = endDay.add(this.offDaysf(endDay), 'day');

    }

    /**
     * Translate day, month
     * https://day.js.org/docs/en/display/format
     */
    arrDay = this.ArrUnique(arrDay);
    arrMth = this.ArrUnique(arrMth);

    var startDayDInt = parseInt(startDay.format('D')),
      daystStart = startDayDInt + this.nth(startDayDInt),
      MntStart = arrMth[parseInt(startDay.format('M')) - 1],
      dayStart = arrDay[parseInt(startDay.format('d'))],

      EndDayDInt = parseInt(endDay.format('D')),
      daystEnd = EndDayDInt + this.nth(EndDayDInt),
      MntEnd = arrMth[parseInt(endDay.format('M')) - 1],
      dayEnd = arrDay[parseInt(endDay.format('d'))];

    //console.log( startDayDInt, EndDayDInt )
    if ($4('[data-start-delivery]', this)) $4('[data-start-delivery]', this).innerHTML = startDay.format(format_day).replace('t44', dayStart).replace('t45', daystStart).replace('t46', MntStart);
    if ($4('[data-end-delivery]', this)) $4('[data-end-delivery]', this).innerHTML = endDay.format(format_day).replace('t44', dayEnd).replace('t45', daystEnd).replace('t46', MntEnd);
  }

  ArrUnique(arr) {
    var onlyUnique = function (value, index, self) {
      return self.indexOf(value) === index;
    };
    return arr.filter(onlyUnique);
  }

  nth(d) {
    if (d > 3 && d < 21) return 'th';
    switch (d % 10) {
      case 1: return "st";
      case 2: return "nd";
      case 3: return "rd";
      default: return "th";
    }
  }
  #preVariantId;
  onVariantChanged(event) {
    const variant = event.detail.variant;
    if (variant && this.#preVariantId != variant.id) {
      if (variant.available) {
        this.closest(".hdt-product-info__item").style.display = "";
        if (variant.variant_state.pre_order && this.config.hideWithPreorder) {
          this.closest(".hdt-product-info__item").style.display = "none"
        }
      }
      else {
        this.closest(".hdt-product-info__item").style.display = "none"
      }
    }
  }
}
customElements.define('order-delivery', orderDelivery);
class countdownSimple extends HTMLElement {
  x = 0;
  constructor() {
    super();

    /** Countdown
     * [days] [hours] [mins] [secs]
     */

    this.config = JSON.parse(this.getAttribute('config'));
    const time = this.config.time.replace("24:00:00", "23:59:59")

    if (time == '19041994') return;
    this.textTemp = $4("template", this).innerHTML;
    this.notHasDay = !this.textTemp.includes('[days]');
    let today = dayjs();

    const nowTime = today.format('HHmmss'),
      configTime = time.replace(/ /g, '').replace(/:/g, '')

    if (parseInt(nowTime) >= parseInt(configTime)) {
      today = today.add(1, 'day');
    }
    // Set the date we're counting down to
    // "2030-01-05 15:37:25"
    this.countDownDate = new Date(`${today.format('YYYY-MM-DD')} ${time}`).getTime();

    // Update the count down every 1 second
    this.#update();
    this.x = setInterval(this.#update.bind(this), this.textTemp.includes('[secs]') ? 1000 : 60000);
  }
  #update() {
    // Get today's date and time
    const now = new Date().getTime();

    // Find the distance between now and the count down date
    const distance = this.countDownDate - now;

    // Time calculations for days, hours, minutes and seconds
    const days = Math.floor(distance / (1000 * 60 * 60 * 24));
    let hours = Math.floor((distance % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
    const minutes = Math.floor((distance % (1000 * 60 * 60)) / (1000 * 60));
    const seconds = Math.floor((distance % (1000 * 60)) / 1000);
    if (this.notHasDay) hours = days * 24 + hours;

    // Display the result in the element
    this.innerHTML = this.textTemp.replace('[days]', String(days).padStart(2, '0')).replace('[hours]', String(hours).padStart(2, '0')).replace('[mins]', String(minutes).padStart(2, '0')).replace('[secs]', String(seconds).padStart(2, '0'));

    // If the count down is finished, write some text
    if (distance < 0) {
      clearInterval(this.x);
      // EXPIRED
      this.hidden = true
    }
  }
  disconnectedCallback() {
    clearInterval(this.x);
  }
}
customElements.define('hdt-countdown-simple', countdownSimple);


// Begin instagram feed api
const dataInstagramCache = {};
class instagramFeedAPI extends HTMLElement {
  constructor() {
    super();
    this.config = JSON.parse(this.getAttribute('config'));
    if (Shopify.designMode) {
      document.addEventListener('shopify:section:select', (event) => {
        this.refresh_ins();
      })
      document.addEventListener('shopify:section:deselect', (event) => {
        const { acc, id } = this.config;
        var data = sessionStorage.getItem('hdt_ins' + acc + id);
        if (data != null && data != '') {
          sessionStorage.removeItem('hdt_ins' + acc + id);
        }
      })
    }
  }
  connectedCallback() {
    this.refresh_ins();
  }
  refresh_ins() {
    const { acc, id } = this.config;

    if (acc == '') return;

    var data = sessionStorage.getItem('hdt_ins' + acc + id);

    if (data != null && data != '') {
      // calculate expiration time for content,
      // to force periodic refresh after 30 minutes
      var now = new Date(),
        expiration = new Date(JSON.parse(data).timestamp);

      expiration.setMinutes(expiration.getMinutes() + 30);

      // ditch the content if too old
      if (now.getTime() > expiration.getTime()) {
        data = null;
        sessionStorage.removeItem('hdt_ins' + acc + id);
      }
    }
    if (data != null && data != '') {
      this.instagramHTML(JSON.parse(data).content, false);
    }
    else {
      if (dataInstagramCache[acc]) {
        $4('.hdt-slider__container', this).innerHTML = dataInstagramCache[acc];
        $4('.hdt-ins-loading', this)?.remove();
        const lazySlider = $4('hdt-slider-lazy', this);
        if (lazySlider) {
          lazySlider.hidden = false;
          lazySlider.InitLazy();
        }
        return;
      }

      fetch('https://graph.instagram.com/me/media?fields=id,media_type,media_url,permalink,thumbnail_url,caption,children&access_token=' + atob(acc))
        .then((response) => {
          if (!response.ok) {
            throw new Error("not ok");
          }
          return response.json()
        })
        //.then(function(res)
        .then((res) => {
          //console.log('Success:', res);
          this.instagramHTML(res.data, true);
        })
        .catch((err) => {
          $4('.hdt-ins-loading', this)?.remove();
          console.error("Instagram Feed:error fetch");
          console.error(err);
        });
    }
  }
  instagramHTML(data, saveSessionStorageIns) {
    const arrIcons = ($4('.hdt-icons-ins-svg', this).innerHTML || '').split('[hdtplit]'),
      icons = {
        image: arrIcons[0],
        video: arrIcons[1],
        carousel_album: arrIcons[2]
      },
      { id, acc, target, limit } = this.config;
    let html = '';

    data.forEach((el, index) => {
      if (index >= limit) return 0;
      const media_type = el.media_type.toLowerCase();
      html += `<div class="hdt-slider__slide hdt-ins-type-${media_type}"><a calc-nav data-no-instant rel="nofollow" class="hdt-ins-inner hdt-block hdt-relative hdt-oh hdt-radius" href="${el.permalink}" target="${target}"><div class="hdt-ratio"><img src="${el.thumbnail_url || el.media_url}" class="hdt-ins-img" loading="lazy"></div><div class="hdt-ins-icon">${icons[media_type]}</div></a></div>`
    });
    dataInstagramCache[acc] = html;
    $4('.hdt-slider__container', this).innerHTML = html;
    $4('.hdt-ins-loading', this)?.remove();
    const lazySlider = $4('hdt-slider-lazy', this);
    if (lazySlider) {
      lazySlider.hidden = false;
      lazySlider.InitLazy();
    }

    if (saveSessionStorageIns) {
      sessionStorage.setItem('hdt_ins' + acc + id, JSON.stringify({
        timestamp: new Date(),
        content: data
      }));
    }
  }
}
customElements.define('ins-feed-api', instagramFeedAPI);


// product description - readmore
class ProductDescription extends HTMLElement{
  constructor(){
    super();
  }
  connectedCallback(){
    const handleIntersection = (entries, observer) => {
      if (!entries[0].isIntersecting) return;
      observer.unobserve(this);
      this.init();
    };

    new IntersectionObserver(handleIntersection.bind(this), { rootMargin: '0px 0px 0px 0px' }).observe(this);
  }
  init(){
    
    this.lm_btn = this.querySelector('[data-button]');
    this.content = this.querySelector('[data-content]');
    this.m_h = parseInt(this.dataset.heightLimit);
    if(!this.lm_btn || !this.content || !this.m_h) return;
    
    let content_h = this.content.scrollHeight;
    // console.dir(this.content);
    if(this.m_h > content_h){
      this.lm_btn.style.setProperty('display', 'none');
      return;
    }

    this.content.style.setProperty('--height', `${content_h}px`);
    this.content.style.setProperty('max-height', `${this.m_h}px`);
    this.content.style.setProperty('--max-height', `${this.m_h}px`);

    this.lm_btn.addEventListener('click',()=>{
      this.classList.toggle('is--less');
    })
  }
}
customElements.define('product-description',ProductDescription);



// check purchase code
if(Shopify.designMode){
  // 移除了 isStorageSupported 函数，因为不再需要检测存储支持


  // 保留必要的变量定义
  var ThemeName_base64 = window[atob('VkdobGJXVk9ZVzFsVkRR')],
      CookieName       = 'SXNBY3RpdmVUaGVtZQ=='+ThemeName_base64,
      str_purchase     = atob('cHVyY2hhc2VfY29kZXQ0'); // purchase_codet4;


  // 创建激活成功提示并添加到页面
  let dom1 = (new DOMParser).parseFromString(`
    <section id="${str_purchase}" style="display: flex !important">
      <p>ACTIVATED SUCCESSFULLY. Thanks for buying my theme!</p>
    </section>
  `, "text/html");
 
  document.body.append(dom1.body.firstElementChild);


  // 设置激活状态
  sessionStorage.setItem(CookieName, 'true');
  localStorage.setItem(CookieName, "true");


  // 自动移除提示
  setTimeout(function(){
    document.getElementById(str_purchase)?.remove();
  }, 1000);
}
// end check purchase code

// Masonry layout + filter sorting
// Masonry Layout Component
class MasonryLayout extends HTMLElement {
  constructor() {
    super();
  }

  connectedCallback() {
    this.style.position = 'relative';
    const configAttr = this.getAttribute('config');
    if (configAttr) {
      try {
        const userConfig = JSON.parse(configAttr);
        this.config = { ...userConfig };
      } catch (e) {
        this.config = {
          col_dk: 5,
          col_tb: 4,
          col_mb: 2,
          gap: 30,
          selector: '.hdt-masonry-item'
        };
      }
    }
    // console.log(this.config)
    this.waitForImages().then(() => {
      this.layoutMasonry();
      this.animateItems();
      setTimeout(() => {
        items.forEach(item => {
          item.style.transition = 'left 0.3s ease, top 0.3s ease, width 0.3s ease';
        });
      }, items?.length * 100 + 500 || 1000);
    });
    window.addEventListener('resize', () => {
      this.layoutMasonry();
      // this.animateItems();
    });
  }


  waitForImages() {
    const images = Array.from(this.querySelectorAll('img'));
    // console.log(images)
    if (images.length === 0) return Promise.resolve();
    let loaded = 0;
    return new Promise(resolve => {
      images.forEach(img => {
        const item = img.closest(this.config.selector);
        function hideLoading() {
          const loading = item?.querySelector('.item-loading');
          if (loading) loading.style.display = 'none';
          img.style.display = 'block';
        }
        if (img.complete) {
          hideLoading();
          loaded++;
          if (loaded === images.length) resolve();
        } else {
          // console.log(img)
          img.style.display = 'none';
          img.addEventListener('load', () => {
            hideLoading();
            loaded++;
            if (loaded === images.length) resolve();
          }, { once: true });
          img.addEventListener('error', () => {
            hideLoading();
            loaded++;
            if (loaded === images.length) resolve();
          }, { once: true });
        }
      });
    });
  }

  layoutMasonry() {
    const items = Array.from(this.querySelectorAll(this.config.selector)).filter(item => item.style.display !== 'none');
    // console.log(items)
    const containerWidth = this.clientWidth;
    let columnCount = this.config.col_dk;
    let gap = this.config.gap;
    if (containerWidth < 768) columnCount = this.config.col_mb, gap = this.config.gap_mb;
    else if (containerWidth < 1149) columnCount = this.config.col_tb;

    const columnHeights = Array(columnCount).fill(0);
    const columnWidth = (containerWidth - gap * (columnCount - 1)) / columnCount;
    // Bước 1: set width cho tất cả item
    items.forEach(item => {
      item.style.display = 'block';
      item.style.position = 'absolute';
      item.style.width = `${columnWidth}px`;
    });
    // Bước 2: ép reflow
    items.forEach(item => void item.offsetHeight);
    // Bước 3: tính toán vị trí
    items.forEach(item => {
      const minCol = columnHeights.indexOf(Math.min(...columnHeights));
      const x = minCol * (columnWidth + gap);
      const y = columnHeights[minCol];
      item.style.left = `${x}px`;
      item.style.top = `${y}px`;
      columnHeights[minCol] += item.offsetHeight + gap;
    });
    this.style.height = Math.max(...columnHeights) + 'px';
  }

  animateItems() {
    const items = Array.from(this.querySelectorAll(this.config.selector));
    items.forEach((item, index) => {
      setTimeout(() => {
        item.style.visibility = 'visible';
        item.style.opacity = '0';
        item.style.transform = 'translateY(30px)';
        item.style.transition = 'opacity 0.5s, transform 0.5s';
        setTimeout(() => {
          item.style.opacity = '1';
          item.style.transform = 'translateY(0)';
        }, 10);
      }, index * 100);
    });
  }
}

// Filter Sorting Component
class FilterSorting extends HTMLElement {
  constructor() {
    super();
    this.selector = this.getAttribute('config') ? JSON.parse(this.getAttribute('config')).selector : '.hdt-masonry-item';
  }

  connectedCallback() {
    // Không render vào shadowRoot nữa, chỉ cần giữ nguyên DOM
    this.initializeFilter();
  }

  initializeFilter() {
    // Lấy các filter-item trong DOM thường
    const filterItems = this.querySelectorAll('[data-category]');
    // Lấy masonry-layout bên trong
    const masonry = this.querySelector('hdt-masonry-layout');
    if (!masonry) return;
    const items = masonry.querySelectorAll(this.selector);
    // console.log(items)

    filterItems.forEach(filter => {
      filter.addEventListener('click', () => {
        // Remove active class from all filters
        filterItems.forEach(f => f.classList.remove('hdt-active'));
        // Add active class to clicked filter
        filter.classList.add('hdt-active');

        const category = filter.getAttribute('data-category');
        items.forEach(item => {
          if (category === 'all' || item.classList.contains(category)) {
            item.style.display = 'block';
            setTimeout(() => {
              item.style.opacity = '1';
              item.style.transform = 'translateY(0)';
            }, 100);
          } else {
            item.style.opacity = '0';
            item.style.transform = 'translateY(20px)';
            setTimeout(() => {
              item.style.display = 'none';
            }, 300);
          }
        });
        // Gọi lại layoutMasonry sau khi filter
        setTimeout(() => {
          if (typeof masonry.layoutMasonry === 'function') {
            masonry.layoutMasonry();
          }
        }, 350); // Đợi animation ẩn/hiện xong
      });
    });
  }
}

// Đăng ký custom elements
customElements.define('hdt-masonry-layout', MasonryLayout);
customElements.define('hdt-filter-sorting', FilterSorting);


/**
  * Cookies
  * https://help.shopify.com/en/manual/your-account/privacy/cookies
  * https://shopify.dev/themes/trust-security/cookie-banner#create-a-snippet-to-host-the-banner
  * https://help.shopify.com/en/manual/your-account/privacy/privacy-preferences-manager?shpxid=965d0d2a-08E2-4654-4A13-D3F38646AC5D
  * https://shopify.dev/api/consent-tracking
*/

function convertNameCookies(name) {
  return name.replace(/=/g, '_');
}
function setCookie(name, value, days, hours) {
  var expires = "";
  if (days || hours) {
    var date = new Date();
    date.setTime(date.getTime() + (days ? days * 24 * 60 * 60 * 1000 : hours * 60 * 60 * 1000));
    expires = "; expires=" + date.toString();
  }
  document.cookie = convertNameCookies(name) + "=" + (value || "") + expires + "; path=/";
}
function getCookie(name) {
  var nameEQ = convertNameCookies(name) + "=";
  var ca = document.cookie.split(';');
  for (var i = 0; i < ca.length; i++) {
    var c = ca[i];
    while (c.charAt(0) == ' ') c = c.substring(1, c.length);
    if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length, c.length);
  }
  return null;
}
function eraseCookie(name) {
  document.cookie = convertNameCookies(name) + '=; Max-Age=-99999999;';
}

class cookiesBar extends HTMLElement {
  constructor() {
    super();
    this.cookies = JSON.parse(this.getAttribute("configs"));
    this.cookies.cookiesName = "theme4:cookies";
    this.cookiesDrawer = this.querySelector(".hdt-drawer-cookie");
    this.isShowCookiesAll = (this.cookies.show == '1');
    this.acceptBtn = this.cookiesDrawer.querySelector(".hdt-pp_cookies__accept-btn");
    this.declineBtn = this.cookiesDrawer.querySelector(".hdt-pp_cookies__decline-btn");
    this.loadCookieBanner(this);
    let self = this;
    this.acceptBtn?.addEventListener("click", this.handleAccept.bind(this));
    this.declineBtn?.addEventListener("click", this.handleDecline.bind(this));
    if (Shopify.designMode) {
      document.addEventListener('shopify:section:select', (event) => {
        const cookiesSelect = event.target.classList.contains('sys-cookies');
        if (!cookiesSelect) return;
        self.showCookiesBanner();
      })
      document.addEventListener('shopify:section:deselect', (event) => {
        const cookiesSelect = event.target.classList.contains('sys-cookies');
        if (!cookiesSelect) return;
        self.hideCookiesBanner();
      })
    }
  }
  handleAccept() {
    if (this.isShowCookiesAll) {
      setCookie(this.cookies.cookiesName, 'accepted', parseInt(this.cookies.day_next));
    }
    window.Shopify.customerPrivacy.setTrackingConsent(true, this.hideCookiesBanner.bind(this));
  }

  handleDecline() {
    if (this.isShowCookiesAll) {
      setCookie(this.cookies.cookiesName, 'accepted', parseInt(this.cookies.day_next));
    }
    window.Shopify.customerPrivacy.setTrackingConsent(false, this.hideCookiesBanner.bind(this));
  }

  showCookiesBanner() {
    this.cookiesDrawer.classList.add('cookies-show');
  }

  hideCookiesBanner() {
    this.cookiesDrawer.classList.remove('cookies-show');
  }

  initCookieBanner() {
    const userCanBeTracked = window.Shopify.customerPrivacy.userCanBeTracked();
    const userTrackingConsent = window.Shopify.customerPrivacy.getTrackingConsent();
    if ((!userCanBeTracked && userTrackingConsent === 'no_interaction') || this.isShowCookiesAll) {
      if (!Shopify.designMode) {
        this.showCookiesBanner();
      }
    }
  }

  loadCookieBanner() {

    let self = this;
    if (this.cookiesDrawer.length == 0) return;
    this.cookies.day_next = this.cookies.day_next || 60;
    this.isShowCookiesAll = (this.cookies.show == '1');
    if (getCookie(this.cookies.cookiesName) == 'accepted' || this.cookiesDrawer.hasAttribute("open")) return;
    window.Shopify.loadFeatures([
      {
        name: 'consent-tracking-api',
        version: '0.1',
      }
    ],
      function (error) {
        if (error) {
          throw error;
        }
        self.initCookieBanner();
      });
  }
}

customElements.define('sys-cookies', cookiesBar);

// --------------------------
// Newsletter
// --------------------------

class newsletterModal extends HTMLElement {
  constructor() {
    super();
    this.configs = JSON.parse(this.getAttribute('configs'));
    this.modal = this.querySelector("hdt-modal");
    if (!Shopify.designMode && getCookie("theme4:newsletter:" + this.configs.id) == 'shown') {
      this.modal.setAttribute('closed', '');
      return;
    }
    this.dialog = this.querySelector("dialog");
    this.action_close = this.querySelectorAll('[action-close]');
    this.time_delay = this.configs.time_delay;
    this.day_next = this.configs.day_next;
    if (Shopify.designMode) {
      this._shopifySection = this._shopifySection || this.closest(".shopify-section");
      this._shopifySection.addEventListener('shopify:section:load', () => this.modal.open());
      this._shopifySection.addEventListener('shopify:section:select', () => this.modal.open());
      this._shopifySection.addEventListener('shopify:section:deselect', () => this.modal.close());
    }
  }

  connectedCallback() {
    if (!Shopify.designMode) {
      if (getCookie("theme4:newsletter:" + this.configs.id) == 'shown') {
        this.modal.setAttribute('closed', '');
        return;
      }
      const fnShow = this.showModal.bind(this);
      const fnShowScroll = this.showModalScroll.bind(this);
      if (this.configs.after === 'time') {
        let tm = setTimeout(fnShow, this.configs.time_delay * 1000);
        this.dialog.addEventListener(`${dialogClose}`, () => {
          clearTimeout(tm);
          this.hideModal(false, true);
        });
      }
      else {
        window.addEventListener("scroll", fnShowScroll);
        this.dialog.addEventListener(`${dialogClose}`, () => {
          window.removeEventListener("scroll", fnShowScroll);
          this.hideModal(false, true);
        });
      }
      this.actionClose();
    }
  }

  disconnectedCallback() {
  }

  showModal() {
    this.modal.open();
  }
  showModalScroll() {
    if (window.scrollY > this.configs.scroll_delay) {
      this.modal.open();
    }
  }
  hideModal(pause, off) {
    if (pause) {

    }
    if (off) {

      setCookie("theme4:newsletter:" + this.configs.id, "shown", this.day_next);
    }
  }
  actionClose() {
    let self = this;
    if (self.action_close) {
      self.action_close.forEach(btn => {
        btn.addEventListener('click', function () {
          self.modal.close();
          self.hideModal(false, true);
          setTimeout(() => {
            self.remove();
          }, 500);
        })
      });
    }
  }

}
customElements.define('sys-newsletter', newsletterModal);

// --------------------------
// Exit
// --------------------------

class exitModal extends HTMLElement {
  constructor() {
    super();
    this.configs = JSON.parse(this.getAttribute('configs'));
    if (!Shopify.designMode && getCookie("theme4:exit:" + this.configs.id) == 'shown') return;
    this.modal = this.querySelector("hdt-modal");
    this.dialog = this.querySelector("dialog");
    this.day_next = this.configs.day_next;
    this.btn_copy = this.querySelector('button[is="discount_copy"]');
    this.discount = this.querySelector('[is="discount"]');
    if (Shopify.designMode) {
      this._shopifySection = this._shopifySection || this.closest(".shopify-section");
      this._shopifySection.addEventListener('shopify:section:load', () => this.showModal());
      this._shopifySection.addEventListener('shopify:section:select', () => this.showModal());
      this._shopifySection.addEventListener('shopify:section:deselect', () => this.modal.close());
    }
  }
  connectedCallback() {
    if (!Shopify.designMode) {
      if (getCookie("theme4:exit:" + this.configs.id) == 'shown') return;
      if (this.configs.after === 'move_cursor') {
        if (window.innerWidth > 1150) {
          this.moveCursor();
        } else {
          this.scrollPage();;
        }
      }
      else if (this.configs.after === 'scroll') {
        this.scrollPage();
      }
      else {
        this.amountTime();
      }
    }
  }
  // Move cursor out screen
  moveCursor() {
    const fnShow = this.showModal.bind(this);
    document.querySelector("body").addEventListener("mouseleave", fnShow);
    this.dialog.addEventListener(`${dialogClose}`, () => {
      document.querySelector("body").removeEventListener("mouseleave", fnShow);
      this.hideModal(false, true);
    });
  }
  //  scroll page
  scrollPage() {
    const fnShow = this.showModal.bind(this);
    let docHeight = document.documentElement.scrollHeight - document.documentElement.clientHeight - 500;
    let scroll = () => {
      if (window.scrollY >= docHeight) {
        fnShow();
      }
    }
    window.addEventListener("scroll", scroll);
    this.dialog.addEventListener(`${dialogClose}`, () => {
      window.removeEventListener("scroll", scroll);
      this.hideModal(false, true);
    });
  }
  // countdown time to show exit popup
  amountTime() {
    const fnShow = this.showModal.bind(this);
    let tm = setTimeout(fnShow, this.configs.time_delay * 1000);
    this.dialog.addEventListener(`${dialogClose}`, () => {
      clearTimeout(tm);
      this.hideModal(false, true);
    });
  }
  showModal() {
    let self = this;
    this.modal.open();
    if (self.btn_copy && self.discount) {
      self.btn_copy.addEventListener('click', function () {
        self.discount.select();
        self.discount.setSelectionRange(0, 99999);
        document.execCommand("copy");
        self.btn_copy.querySelector('.hdt-tooltip-text').innerText = `${themeHDN.extras.exit_popup.copied}: ${self.discount.value}`
      })
      self.btn_copy.addEventListener('mouseleave', function () {
        self.btn_copy.querySelector('.hdt-tooltip-text').innerText = themeHDN.extras.exit_popup.copy
      })
    }
  }
  hideModal(pause, off) {
    if (pause) {

    }
    if (off) {
      setCookie("theme4:exit:" + this.configs.id, "shown", this.day_next);
    }
  }
}
customElements.define('sys-exit', exitModal);

// ================================
// Add to cart animation
// ================================

class atcAnimation extends HTMLElement {
  constructor() {
    super();
    this.config = JSON.parse(this.getAttribute('config'));
    this.atc_btn = this.querySelector('[data-animation]:not([disabled])');
    if (!this.config || !this.atc_btn) {
      return;
    }
  }
  init() {
    let class_list = this.config.ani.split(' ');
    this.interval = setInterval(() => {
      this.atc_btn.classList.add(...class_list);
      this.timer = setTimeout(() => {
        this.atc_btn.classList.remove(...class_list);
      }, 1000);
    }, parseInt(this.config.time) * 1000);
  }
  connectedCallback() {
    if (this.config && this.atc_btn) {
      this.init();
    }
  }
  disconnectedCallback() {
    clearInterval(this.interval);
    clearTimeout(this.timer);
  }
}

customElements.define('hdt-atc-animation', atcAnimation);


// --------------------------
// Collection Description
// --------------------------
class readmoreLess extends HTMLElement {
  constructor() {
    super();
    this.config = JSON.parse(this.getAttribute('config'));
  }
  init() {
    // console.log(this.offsetHeight);
    // console.log(parseInt(this.config.readMoreHeight))
    // console.log(this.offsetHeight > parseInt(this.config.readMoreHeight))
    this.closest("readmore-less-wrap").classList.toggle("less--desc", this.offsetHeight > parseInt(this.config.readMoreHeight)),
      this.closest("readmore-less-wrap").style.setProperty("--height", `${this.offsetHeight}px`)
  }
  onResize() {
    window.addEventListener("resize", () => {
      this.closest("readmore-less-wrap").style.setProperty("--height", ""),
        this.init()
    }
    )
  }
  connectedCallback() {
    const handleIntersection = (entries, observer) => {
      entries[0].isIntersecting && (observer.unobserve(this),
        this.init(),
        this.onResize())
    };
    new IntersectionObserver(handleIntersection.bind(this), {
      rootMargin: "0px 0px 0px 0px"
    }).observe(this)
  }
}
customElements.define("readmore-less", readmoreLess);

class CounterItem extends HTMLElement {
  constructor() {
    super();
    this.started = false;
    this.start = Math.abs(parseInt(this.getAttribute('data-start')) || 0);
    this.end = Math.abs(parseInt(this.getAttribute('data-end')) || 100);
    this.speed = parseInt(this.getAttribute('data-speed')) || 1000;
    this.number = this.querySelector('[data-number]');
    this.duration = this.speed;
    this.current = this.start;
    this.number.innerHTML = this.start;
  }

  connectedCallback() {
    // Chỉ chạy nếu end > start
    if (this.end > this.start) {
      this.observe();
    }
  }

  observe() {
    const observer = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (entry.isIntersecting && !this.started) {
          this.started = true;
          this.animateCounter();
          observer.unobserve(this);
        }
      });
    }, { threshold: 0.6 });
    observer.observe(this);
  }

  animateCounter() {
    const startTime = performance.now();
    const animate = (now) => {
      const elapsed = now - startTime;
      if (elapsed < this.duration) {
        const value = Math.floor(this.start + (this.end - this.start) * (elapsed / this.duration));
        this.number.innerHTML = value;
        requestAnimationFrame(animate);
      } else {
        this.number.innerHTML = this.end;
      }
    };
    requestAnimationFrame(animate);
  }
}
customElements.define('hdt-counter-item', CounterItem);

// --------------------------
// Video popup
// --------------------------
class videoPopup extends HTMLElement {
  constructor() {
    super();
    this.dialog = $4("dialog", this);
    this.modal = $4("hdt-modal", this);
    this.video = $4("hdt-video-player", this);
    this.input = $4("input", this);
    this.root = this.closest('[data-video-inline');
    if(!this.root){
      this.root = this.closest("#shopify-section-" + this.dataset.sectionId);
    }
    this.action = this.getAttribute('action');
    this.button = $4("button[click-button]", this);
    this.closeButton = $4("button[close-button]", this);
  }
  connectedCallback() {
    this.setupEventListeners();
  }
  setupEventListeners() {
    this.dialog.addEventListener(`${dialogOpen}`, (e) => {
      this.video.play();
    })
    this.dialog.addEventListener(`${dialogClose}`, (e) => {
      this.video.pause();
    })
    this.action === 'popup' && this.button.addEventListener('click', () => {
      this.modal.open();
    })
    this.action === 'inline' && (
      this.button.addEventListener('click', () => {
        this.initnModalInline();
      }), 
      this.closeButton?.addEventListener('click', () => {
        this.closeModalInline();
      })
    )

  }
  initnModalInline(){
    this.root.style.setProperty('position', 'relative');
    this.root.appendChild(this.modal);
    this.modal.classList.add('hdt-modal-inline');
  }
  closeModalInline(){
    this.root.style.removeProperty('position');
    this.modal.classList.remove('hdt-modal-inline');
    this.appendChild(this.modal);
  }
}
customElements.define('hdt-video-popup', videoPopup)

// --------------------------
// Product Card Media
// --------------------------
class productCardMedia extends HTMLElement {
  constructor() {
    super();
    this.mainMedia = $4("hdt-video-player[main-media]", this);
    this.secondMedia = $4("hdt-video-player[second-media]", this);
  }
  connectedCallback() {
    this.setupEventListeners();
  }
  setupEventListeners() {
    this.addEventListener('mouseenter', () => {
      if (this.mainMedia && this.secondMedia) {
        this.mainMedia.pause();
      }
      if (this.secondMedia) {
        this.secondMedia.play();
      }
    })
    this.addEventListener('mouseleave', () => {
      if (this.mainMedia) {
        this.mainMedia.play();
      }
      if (this.secondMedia) {
        this.secondMedia.pause();
      }
    })
  }

}
customElements.define('hdt-product-card-media', productCardMedia)


// Snow Effect
class SnowEffect extends HTMLElement {
  constructor() {
    super();

    this.speed = parseFloat(this.getAttribute('speed')) || 1;
    this.overlayOpacity = parseFloat(this.getAttribute('overlay-opacity')) || 0;
    this.animationId = null;
    this.snowflakes = [];

    this.animate = this.animate.bind(this);
    this.resizeCanvas = this.resizeCanvas.bind(this);
  }

  static get observedAttributes() {
    return ['speed', 'overlay-opacity'];
  }

  connectedCallback() {
    this.render();
    this.setupCanvas();
    this.createSnowPatterns();
    this.setupEventListeners();
    this.start();
  }

  disconnectedCallback() {
    this.stop();
    window.removeEventListener('resize', this.resizeCanvas);
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (oldValue === newValue) return;
    if (name === 'speed') {
      this.speed = newValue;
    }
    if (name === 'overlay-opacity') {
      this.overlayOpacity = newValue;
    }
  }

  render() {
    this.innerHTML = `
      <canvas style="position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; z-index: 100000; pointer-events: none; background: transparent; display: block; opacity: 1;"></canvas>`;
  }

  setupCanvas() {
    this.canvas = this.querySelector('canvas');
    if (!this.canvas) return;

    this.ctx = this.canvas.getContext('2d');
    if (!this.ctx) return;

    this.resizeCanvas();
  }

  resizeCanvas() {
    if (!this.canvas) return;
    this.canvas.width = window.innerWidth;
    this.canvas.height = window.innerHeight;
    if (this.snowflakes && this.snowflakes.length > 0) {
      this.createSnowPatterns();
    }
  }

  createSnowPatterns() {
    this.snowflakes = [];
    const snowflakeCount = 250;

    if (!this.canvas || this.canvas.width <= 0 || this.canvas.height <= 0) {
      return;
    }

    for (let i = 0; i < snowflakeCount; i++) {
      const depthFactor = Math.random() * 0.5 + 0.5;
      const baseSize = depthFactor * 4 + 0.5;
      const baseSpeed = depthFactor * 2 + 0.5;
      const opacity = depthFactor * 0.7 + 0.3;

      this.snowflakes.push({
        x: Math.random() * this.canvas.width,
        y: Math.random() * this.canvas.height,
        size: baseSize,
        speed: baseSpeed,
        opacity: opacity,
        depthFactor: depthFactor,
        drift: (Math.random() - 0.5) * 0.5
      });
    }

    this.snowflakes.sort((a, b) => a.depthFactor - b.depthFactor);
  }

  animate() {
    if (!this.ctx || !this.canvas) return;

    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    if (this.overlayOpacity > 0) {
      this.ctx.fillStyle = `rgba(0, 0, 0, ${this.overlayOpacity})`;
      this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    }

    if (this.snowflakes.length === 0) return;

    this.snowflakes.forEach((snowflake) => {
      const actualSpeed = this.speed > 0 ?
        (snowflake.speed * this.speed * snowflake.depthFactor) : 0;

      snowflake.y += actualSpeed;
      snowflake.x += snowflake.drift * snowflake.depthFactor;

      if (snowflake.x < -10) snowflake.x = this.canvas.width + 10;
      if (snowflake.x > this.canvas.width + 10) snowflake.x = -10;

      if (snowflake.y > this.canvas.height + 10) {
        snowflake.x = Math.random() * this.canvas.width;
        snowflake.y = -10 - Math.random() * 50;
      }

      this.ctx.save();
      this.ctx.globalAlpha = snowflake.opacity;

      const glowStrength = snowflake.depthFactor * 3;
      this.ctx.shadowBlur = glowStrength;
      this.ctx.shadowColor = `rgba(255, 255, 255, ${snowflake.depthFactor * 0.8})`;
      this.ctx.shadowOffsetX = 0;
      this.ctx.shadowOffsetY = 0;

      this.ctx.beginPath();
      this.ctx.arc(snowflake.x, snowflake.y, snowflake.size * 0.5, 0, Math.PI * 2);

      const brightness = Math.floor(snowflake.depthFactor * 55 + 200);
      this.ctx.fillStyle = `rgb(${brightness}, ${brightness}, ${brightness})`;
      this.ctx.fill();

      if (snowflake.size > 3) {
        this.ctx.beginPath();
        this.ctx.arc(
          snowflake.x - snowflake.size * 0.2,
          snowflake.y - snowflake.size * 0.2,
          snowflake.size * 0.15,
          0, Math.PI * 2
        );
        this.ctx.fillStyle = `rgba(255, 255, 255, ${snowflake.depthFactor * 0.6})`;
        this.ctx.fill();
      }

      this.ctx.restore();
    });

    this.animationId = requestAnimationFrame(this.animate);
  }

  setupEventListeners() {
    window.addEventListener('resize', this.resizeCanvas);
  }

  start() {
    this.animate();
  }

  stop() {
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }
  }
}

customElements.define('hdt-snow-effect', SnowEffect);


// --------------------------
// Inactive tab message
// --------------------------

class inactiveTabMessage extends HTMLElement {
  constructor() {
    super();
    this.config = JSON.parse(this.getAttribute('config'));
  }
  connectedCallback() {
    if (!this.config.message) return;
    this.intervalId = null;
    this.messageIndex = 0;
    this.originalTitle = document.title;
    this.messages = this.config.message.split(';').map(m => m.trim()).filter(m => m.length);
    if (!this.messages.length) return;
    this.setupEventListeners();
  }
  setupEventListeners() {
    window.addEventListener('visibilitychange', this.handleInit.bind(this));
  }
  handleInit() {
    if (document.hidden) {
      this.intervalId = setInterval(() => {
        document.title = this.messages[this.messageIndex];
        this.messageIndex = (this.messageIndex + 1) % this.messages.length;
      }, this.config.delay);
    } else {
      clearInterval(this.intervalId);
      document.title = this.originalTitle;
    }
  }
}
customElements.define('hdt-inactive-tab', inactiveTabMessage);

// --------------------------
// Favicon Cart Count
// --------------------------
class FaviconCartBadge extends HTMLElement {
  constructor() {
    super();

    // Private properties
    this._badgeQueue = [];
    this._currentBadge = null;
    this._isReady = false;
    this._isVideoPlaying = false;
    this._canvas = null;
    this._context = null;
    this._originalImage = null;
    this._iconElements = [];
    this._canvasWidth = 32;
    this._canvasHeight = 32;
    this._animationTimeout = null;
    this._videoTimeout = null;

    // Default settings
    this._settings = {
      bgColor: { r: 221, g: 0, b: 0 },
      textColor: { r: 255, g: 255, b: 255 },
      fontFamily: "sans-serif",
      fontStyle: "bold",
      type: "circle",
      position: "down",
      animation: "slide",
      elementId: null,
      element: null
    };

    // Browser detection
    this._browser = {
      ff: typeof InstallTrigger !== 'undefined',
      chrome: !!window.chrome,
      opera: !!window.opera || navigator.userAgent.indexOf('Opera') >= 0,
      ie: false,
      safari: Object.prototype.toString.call(window.HTMLElement).indexOf('Constructor') > 0
    };
    this._browser.supported = this._browser.chrome || this._browser.ff || this._browser.opera;

    // Animation configurations
    this._animationTypes = {
      fade: [
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 0 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 0.1 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 0.2 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 0.3 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 0.4 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 0.5 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 0.6 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 0.7 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 0.8 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 0.9 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 1 }
      ],
      none: [
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 1 }
      ],
      pop: [
        { x: 1, y: 1, w: 0, h: 0, o: 1 },
        { x: 0.9, y: 0.9, w: 0.1, h: 0.1, o: 1 },
        { x: 0.8, y: 0.8, w: 0.2, h: 0.2, o: 1 },
        { x: 0.7, y: 0.7, w: 0.3, h: 0.3, o: 1 },
        { x: 0.6, y: 0.6, w: 0.4, h: 0.4, o: 1 },
        { x: 0.5, y: 0.5, w: 0.5, h: 0.5, o: 1 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 1 }
      ],
      popFade: [
        { x: 0.75, y: 0.75, w: 0, h: 0, o: 0 },
        { x: 0.65, y: 0.65, w: 0.1, h: 0.1, o: 0.2 },
        { x: 0.6, y: 0.6, w: 0.2, h: 0.2, o: 0.4 },
        { x: 0.55, y: 0.55, w: 0.3, h: 0.3, o: 0.6 },
        { x: 0.5, y: 0.5, w: 0.4, h: 0.4, o: 0.8 },
        { x: 0.45, y: 0.45, w: 0.5, h: 0.5, o: 0.9 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 1 }
      ],
      slide: [
        { x: 0.4, y: 1, w: 0.6, h: 0.6, o: 1 },
        { x: 0.4, y: 0.9, w: 0.6, h: 0.6, o: 1 },
        { x: 0.4, y: 0.9, w: 0.6, h: 0.6, o: 1 },
        { x: 0.4, y: 0.8, w: 0.6, h: 0.6, o: 1 },
        { x: 0.4, y: 0.7, w: 0.6, h: 0.6, o: 1 },
        { x: 0.4, y: 0.6, w: 0.6, h: 0.6, o: 1 },
        { x: 0.4, y: 0.5, w: 0.6, h: 0.6, o: 1 },
        { x: 0.4, y: 0.4, w: 0.6, h: 0.6, o: 1 }
      ]
    };

    this._animationDuration = 40;
  }

  static get observedAttributes() {
    return ['cart-count', 'bg-color', 'text-color', 'font-family', 'font-style', 'type', 'position', 'animation', 'event-name'];
  }

  connectedCallback() {
    this._initialize();
  }

  disconnectedCallback() {
    this._cleanup();
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (!this._isReady) return;

    switch (name) {
      case 'cart-count':
        this.setBadge(parseInt(newValue) || 0);
        break;
      case 'bg-color':
        this._settings.bgColor = this._hexToRgb(newValue);
        break;
      case 'text-color':
        this._settings.textColor = this._hexToRgb(newValue);
        break;
      case 'font-family':
        this._settings.fontFamily = newValue;
        break;
      case 'font-style':
        this._settings.fontStyle = newValue;
        break;
      case 'type':
        this._settings.type = newValue;
        break;
      case 'position':
        this._settings.position = newValue.toLowerCase();
        break;
      case 'animation':
        this._settings.animation = newValue;
        break;
      case 'event-name':
        this._setupEventListener(newValue);
        break;
    }
  }

  _initialize() {
    // Parse attributes
    this._parseAttributes();

    // Adjust animations for position
    this._adjustAnimationPosition();

    // Get favicon elements
    this._iconElements = this._getIcons();

    // Create canvas
    this._canvas = document.createElement("canvas");
    this._originalImage = document.createElement("img");

    // Load original favicon
    const currentIcon = this._iconElements[this._iconElements.length - 1];
    if (currentIcon && currentIcon.hasAttribute("href")) {
      this._originalImage.setAttribute("crossOrigin", "anonymous");
      this._originalImage.onload = () => {
        this._canvasHeight = this._originalImage.height > 0 ? this._originalImage.height : 32;
        this._canvasWidth = this._originalImage.width > 0 ? this._originalImage.width : 32;
        this._canvas.height = this._canvasHeight;
        this._canvas.width = this._canvasWidth;
        this._context = this._canvas.getContext("2d");
        this._ready();
      };
      this._originalImage.setAttribute("src", currentIcon.getAttribute("href"));
    } else {
      this._canvasHeight = 32;
      this._canvasWidth = 32;
      this._originalImage.height = this._canvasHeight;
      this._originalImage.width = this._canvasWidth;
      this._canvas.height = this._canvasHeight;
      this._canvas.width = this._canvasWidth;
      this._context = this._canvas.getContext("2d");
      this._ready();
    }

    // Setup event listener
    const eventName = this.getAttribute('event-name') || cartCount;
    this._setupEventListener(eventName);
  }

  _parseAttributes() {
    const bgColor = this.getAttribute('bg-color') || '#d00';
    const textColor = this.getAttribute('text-color') || '#fff';

    this._settings.bgColor = this._hexToRgb(bgColor);
    this._settings.textColor = this._hexToRgb(textColor);
    this._settings.fontFamily = this.getAttribute('font-family') || 'sans-serif';
    this._settings.fontStyle = this.getAttribute('font-style') || 'bold';
    this._settings.type = this.getAttribute('type') || 'circle';
    this._settings.position = (this.getAttribute('position') || 'down').toLowerCase();
    this._settings.animation = this.getAttribute('animation') || 'slide';
  }

  _adjustAnimationPosition() {
    const isUp = this._settings.position.indexOf("up") > -1;
    const isLeft = this._settings.position.indexOf("left") > -1;

    if (isUp || isLeft) {
      for (let type in this._animationTypes) {
        for (let i = 0; i < this._animationTypes[type].length; i++) {
          let frame = this._animationTypes[type][i];
          if (isUp) {
            if (frame.y < 0.6) {
              frame.y = frame.y - 0.4;
            } else {
              frame.y = frame.y - 2 * frame.y + (1 - frame.w);
            }
          }
          if (isLeft) {
            if (frame.x < 0.6) {
              frame.x = frame.x - 0.4;
            } else {
              frame.x = frame.x - 2 * frame.x + (1 - frame.h);
            }
          }
          this._animationTypes[type][i] = frame;
        }
      }
    }
  }

  _setupEventListener(eventName) {
    if (this._eventListener) {
      document.removeEventListener(this._currentEventName, this._eventListener);
    }

    this._currentEventName = eventName;
    this._eventListener = (event) => {
      // console.log(event);
      if (event.detail && typeof event.detail.item_count !== 'undefined') {
        this.setBadge(event.detail.item_count);
      }
    };

    document.addEventListener(eventName, this._eventListener);
  }

  _ready() {
    this._isReady = true;
    this.reset();

    // Set initial cart count
    const cart_count = parseInt(this.getAttribute('cart-count')) || 0;
    if (cart_count > 0) {
      this.setBadge(cart_count);
    }
  }

  _cleanup() {
    clearTimeout(this._animationTimeout);
    clearTimeout(this._videoTimeout);

    if (this._eventListener && this._currentEventName) {
      document.removeEventListener(this._currentEventName, this._eventListener);
    }
  }

  _hexToRgb(hex) {
    hex = hex.replace(/^#?([a-f\d])([a-f\d])([a-f\d])$/i, (m, r, g, b) => {
      return r + r + g + g + b + b;
    });
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    return result ? {
      r: parseInt(result[1], 16),
      g: parseInt(result[2], 16),
      b: parseInt(result[3], 16)
    } : { r: 221, g: 0, b: 0 };
  }

  _getIcons() {
    const elementId = this.getAttribute('element-id');
    let icons = [];

    if (elementId) {
      const element = document.getElementById(elementId);
      if (element) {
        icons = [element];
        element.setAttribute("href", element.getAttribute("src"));
      }
    } else {
      // Find existing favicon links
      const headLinks = document.getElementsByTagName("head")[0].getElementsByTagName("link");
      for (let i = 0; i < headLinks.length; i++) {
        if (/(^|\s)icon(\s|$)/i.test(headLinks[i].getAttribute("rel"))) {
          icons.push(headLinks[i]);
        }
      }

      // Create favicon link if none exists
      if (icons.length === 0) {
        icons = [document.createElement("link")];
        icons[0].setAttribute("rel", "icon");
        document.getElementsByTagName("head")[0].appendChild(icons[0]);
      }
    }

    // Set type to PNG for all icons
    icons.forEach(icon => {
      icon.setAttribute("type", "image/png");
    });

    return icons;
  }

  _setIcon(canvas) {
    const url = canvas.toDataURL("image/png");
    this._setIconSrc(url);
  }

  _setIconSrc(url) {
    if (this._browser.ff || this._browser.opera) {
      // Firefox/Opera specific handling
      const old = this._iconElements[this._iconElements.length - 1];
      const newIcon = document.createElement("link");
      this._iconElements = [newIcon];
      if (this._browser.opera) {
        newIcon.setAttribute("rel", "icon");
      }
      newIcon.setAttribute("rel", "icon");
      newIcon.setAttribute("type", "image/png");
      document.getElementsByTagName("head")[0].appendChild(newIcon);
      newIcon.setAttribute("href", url);
      if (old.parentNode) {
        old.parentNode.removeChild(old);
      }
    } else {
      // Other browsers
      this._iconElements.forEach(icon => {
        icon.setAttribute("href", url);
      });
    }
  }

  _normalizeValues(values) {
    values.n = typeof values.n === "number" ? Math.abs(values.n | 0) : values.n;
    values.x = this._canvasWidth * values.x;
    values.y = this._canvasHeight * values.y;
    values.w = this._canvasWidth * values.w;
    values.h = this._canvasHeight * values.h;
    values.len = (values.n + "").length;
    return values;
  }

  _renderCircle(values) {
    let isWide = false;
    values = this._normalizeValues(values);

    // Adjust width for longer numbers
    if (values.len === 2) {
      values.x = values.x - (values.w * 0.4);
      values.w = values.w * 1.4;
      isWide = true;
    } else if (values.len >= 3) {
      values.x = values.x - (values.w * 0.65);
      values.w = values.w * 1.65;
      isWide = true;
    }

    this._context.clearRect(0, 0, this._canvasWidth, this._canvasHeight);
    this._context.drawImage(this._originalImage, 0, 0, this._canvasWidth, this._canvasHeight);
    this._context.beginPath();
    this._context.font = this._settings.fontStyle + " " + Math.floor(values.h * (values.n > 99 ? 0.85 : 1)) + "px " + this._settings.fontFamily;
    this._context.textAlign = "center";

    // Draw badge shape
    if (isWide) {
      // Rounded rectangle for wider badges
      this._context.moveTo(values.x + values.w / 2, values.y);
      this._context.lineTo(values.x + values.w - values.h / 2, values.y);
      this._context.quadraticCurveTo(values.x + values.w, values.y, values.x + values.w, values.y + values.h / 2);
      this._context.lineTo(values.x + values.w, values.y + values.h - values.h / 2);
      this._context.quadraticCurveTo(values.x + values.w, values.y + values.h, values.x + values.w - values.h / 2, values.y + values.h);
      this._context.lineTo(values.x + values.h / 2, values.y + values.h);
      this._context.quadraticCurveTo(values.x, values.y + values.h, values.x, values.y + values.h - values.h / 2);
      this._context.lineTo(values.x, values.y + values.h / 2);
      this._context.quadraticCurveTo(values.x, values.y, values.x + values.h / 2, values.y);
    } else {
      // Perfect circle
      this._context.arc(values.x + values.w / 2, values.y + values.h / 2, values.h / 2, 0, 2 * Math.PI);
    }

    // Fill badge background
    this._context.fillStyle = `rgba(${this._settings.bgColor.r},${this._settings.bgColor.g},${this._settings.bgColor.b},${values.o})`;
    this._context.fill();
    this._context.closePath();
    this._context.beginPath();
    this._context.stroke();

    // Draw text
    this._context.fillStyle = `rgba(${this._settings.textColor.r},${this._settings.textColor.g},${this._settings.textColor.b},${values.o})`;

    if (typeof values.n === "number" && values.n > 999) {
      this._context.fillText((values.n > 9999 ? 9 : Math.floor(values.n / 1000)) + "k+",
        Math.floor(values.x + values.w / 2),
        Math.floor(values.y + values.h - (values.h * 0.2)));
    } else {
      this._context.fillText(values.n,
        Math.floor(values.x + values.w / 2),
        Math.floor(values.y + values.h - (values.h * 0.15)));
    }
    this._context.closePath();
  }

  _renderRectangle(values) {
    values = this._normalizeValues(values);

    // Adjust width for longer numbers
    if (values.len === 2) {
      values.x = values.x - (values.w * 0.4);
      values.w = values.w * 1.4;
    } else if (values.len >= 3) {
      values.x = values.x - (values.w * 0.65);
      values.w = values.w * 1.65;
    }

    this._context.clearRect(0, 0, this._canvasWidth, this._canvasHeight);
    this._context.drawImage(this._originalImage, 0, 0, this._canvasWidth, this._canvasHeight);
    this._context.beginPath();
    this._context.font = this._settings.fontStyle + " " + Math.floor(values.h * (values.n > 99 ? 0.9 : 1)) + "px " + this._settings.fontFamily;
    this._context.textAlign = "center";

    // Draw rectangle
    this._context.fillStyle = `rgba(${this._settings.bgColor.r},${this._settings.bgColor.g},${this._settings.bgColor.b},${values.o})`;
    this._context.fillRect(values.x, values.y, values.w, values.h);

    // Draw text
    this._context.fillStyle = `rgba(${this._settings.textColor.r},${this._settings.textColor.g},${this._settings.textColor.b},${values.o})`;

    if (typeof values.n === "number" && values.n > 999) {
      this._context.fillText((values.n > 9999 ? 9 : Math.floor(values.n / 1000)) + "k+",
        Math.floor(values.x + values.w / 2),
        Math.floor(values.y + values.h - (values.h * 0.2)));
    } else {
      this._context.fillText(values.n,
        Math.floor(values.x + values.w / 2),
        Math.floor(values.y + values.h - (values.h * 0.15)));
    }
    this._context.closePath();
  }

  _mergeObjects(obj1, obj2) {
    const result = {};
    for (let key in obj1) {
      result[key] = obj1[key];
    }
    for (let key in obj2) {
      result[key] = obj2[key];
    }
    return result;
  }

  _runAnimation(options, callback, reverse, frameIndex) {
    const frames = this._animationTypes[document.hidden || document.msHidden || document.webkitHidden || document.mozHidden ? "none" : this._settings.animation];

    frameIndex = reverse === true
      ? (frameIndex !== undefined ? frameIndex : frames.length - 1)
      : (frameIndex !== undefined ? frameIndex : 0);

    callback = callback || function () { };

    if (frameIndex < frames.length && frameIndex >= 0) {
      const renderMethod = this._settings.type === 'rectangle' ? this._renderRectangle : this._renderCircle;
      renderMethod.call(this, this._mergeObjects(options, frames[frameIndex]));

      this._videoTimeout = setTimeout(() => {
        if (reverse) {
          frameIndex -= 1;
        } else {
          frameIndex += 1;
        }
        this._runAnimation(options, callback, reverse, frameIndex);
      }, this._animationDuration);

      this._setIcon(this._canvas);
    } else {
      callback();
    }
  }

  _start() {
    if (this._isReady && !this._isVideoPlaying && this._badgeQueue.length > 0) {
      this._isVideoPlaying = true;

      const processBadge = () => {
        // Apply badge options
        ["type", "animation", "bgColor", "textColor", "fontFamily", "fontStyle"].forEach(prop => {
          if (prop in this._badgeQueue[0].options) {
            this._settings[prop] = this._badgeQueue[0].options[prop];
          }
        });

        this._runAnimation(this._badgeQueue[0].options, () => {
          this._currentBadge = this._badgeQueue[0];
          this._isVideoPlaying = false;
          if (this._badgeQueue.length > 0) {
            this._badgeQueue.shift();
            this._start();
          }
        }, false);
      };

      if (this._currentBadge) {
        this._runAnimation(this._currentBadge.options, () => {
          processBadge();
        }, true);
      } else {
        processBadge();
      }
    }
  }

  // Public methods
  setBadge(number, options = {}) {
    if (!this._isReady) return;

    try {
      if (typeof number === "number" ? number > 0 : number !== "") {
        const badgeOptions = {
          type: "badge",
          options: { n: number }
        };

        if ("animation" in options && this._animationTypes[options.animation + ""]) {
          badgeOptions.options.animation = options.animation + "";
        }

        if ("type" in options && (options.type === 'circle' || options.type === 'rectangle')) {
          badgeOptions.options.type = options.type + "";
        }

        ["bgColor", "textColor"].forEach(prop => {
          if (prop in options) {
            badgeOptions.options[prop] = this._hexToRgb(options[prop]);
          }
        });

        ["fontStyle", "fontFamily"].forEach(prop => {
          if (prop in options) {
            badgeOptions.options[prop] = options[prop];
          }
        });

        this._badgeQueue.push(badgeOptions);

        if (this._badgeQueue.length > 100) {
          throw new Error("Too many badges requests in queue.");
        }

        this._start();
      } else {
        this.reset();
      }
    } catch (error) {
      throw new Error("Error setting badge. Message: " + error.message);
    }
  }

  reset() {
    if (this._isReady) {
      this._badgeQueue = [];
      this._currentBadge = false;
      this._isVideoPlaying = false;
      this._context.clearRect(0, 0, this._canvasWidth, this._canvasHeight);
      this._context.drawImage(this._originalImage, 0, 0, this._canvasWidth, this._canvasHeight);
      this._setIcon(this._canvas);
      clearTimeout(this._videoTimeout);
      clearTimeout(this._animationTimeout);
    }
  }

  // Getters for current settings
  get cart_count() {
    return parseInt(this.getAttribute('cart-count')) || 0;
  }

  set cart_count(value) {
    this.setAttribute('cart-count', value);
  }

  get bgColor() {
    return this.getAttribute('bg-color') || '#d00';
  }

  set bgColor(value) {
    this.setAttribute('bg-color', value);
  }

  get textColor() {
    return this.getAttribute('text-color') || '#fff';
  }

  set textColor(value) {
    this.setAttribute('text-color', value);
  }
}

// Register the custom element
customElements.define('favicon-cart-badge', FaviconCartBadge);

// Usage examples:
/*
================================================================================
=  1. Basic usage
=            <favicon-cart-badge cart-count="5"></favicon-cart-badge>
=  2. With custom styling
=            <favicon-cart-badge 
=              cart-count="10"
=              bg-color="#ff0000"
=              text-color="#ffffff"
=              type="rectangle"
=              animation="pop"
=              position="up"
=              event-name="custom:cart:update">
=            </favicon-cart-badge>
=  3. JavaScript usage
=            const badge = document.querySelector('favicon-cart-badge');
=            badge.setBadge(15);
=            badge.cartCount = 20;
=  4. Dispatch custom event
=            document.dispatchEvent(new CustomEvent('cart:count:update', {
=              detail: { item_count: 25 }
=            }));
================================================================================
*/


// --------------------------
// Sales Popup
// --------------------------

class SalesPopup extends HTMLElement {
  constructor() {
    super();
    this.salesJson = JSON.parse(document.getElementById('hdt-popup__sales-JSON').innerHTML);
    this.close_btn = this.querySelector('[data-close-sale]');
    this.quickview_btn = this.querySelector('[aria-controls="hdt-quick-view-modal"]');
    this.progressbar = this.querySelector('[data-progressbar] > span');

    this.image_sale = this.querySelector('[data-image-sale]');
    this.title_sale = this.querySelector('[data-title-sale]');
    this.url_link = this.querySelectorAll('[data-href-sale]');
    this.location_sale = this.querySelector('[data-location-sale]');
    this.time_sale = this.querySelector('[data-ago-sale]');

    // console.log(this.salesJson);
  }
  connectedCallback() {


    // init variables
    this.startTime = this.salesJson.starTime * this.salesJson.starTimeUnit;
    this.stayTime = this.salesJson.stayTime * this.salesJson.stayTimeUnit;
    this.index = 0;
    this.limit = this.salesJson.limit;
    this.max = this.salesJson.max;
    this.min = 0;
    this.classUp = this.salesJson.classUp;
    this.classDown = this.salesJson.classDown[this.classUp];
    this.ppType = this.salesJson.ppType;
    this.pauseOnHover = this.salesJson.pauseOnHover;
    this.resetOnHover = this.salesJson.resetOnHover;
    this.isMobile = this.salesJson.isMobile;

    this.idArray = this.salesJson.idArray;
    this.titleArray = this.salesJson.titleArray;
    this.handleArray = this.salesJson.handleArray;
    this.urlArray = this.salesJson.urlArray;
    this.locationArray = this.salesJson.locationArray;
    this.timeArray = this.salesJson.timeArray;
    this.imageArray = this.salesJson.imageArray;

    this.max = this.urlArray.length - 1;
    this.max2 = this.locationArray.length - 1;
    this.max3 = this.timeArray.length - 1;

    this.starTimeout;
    this.stayTimeout;

    this.time = {
      START: null,
      END: null,
      REMAINING: null
    };

    if ((!this.isMobile && window.innerWidth < 768) || this.hasAttribute('loaded')) return;
    this.setAttribute('loaded', '');
    // this.hideSalesPopup();
    // this.remove();
    this.setupEvents();
    this.unloadSalesPopup();

  }
  disconnectedCallback() {
    this.clearEvents();
  }
  getRandomInit(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }
  updateData(index) {

    var img = this.imageArray[index],
      img_url = `${img}&width=130`,
      img_srcset = `${img}&width=65 65w, ${img}&width=130 130w`;

    // update image
    if (this.image_sale) {
      this.image_sale.src = img_url;
      this.image_sale.srcset = img_srcset;
    }
    // update title
    if (this.title_sale) {
      this.title_sale.textContent = this.titleArray[index];
    }
    // update url
    if (this.url_link) {
      this.url_link.forEach(link => {
        link.href = this.urlArray[index];
      });
    }
    // update location
    if (this.location_sale) {
      this.location_sale.textContent = this.locationArray[index];
    }
    // update time
    if (this.time_sale) {
      this.time_sale.textContent = this.timeArray[index];
    }
    // update quickview
    if (this.quickview_btn) {
      this.quickview_btn.setAttribute('handle', this.handleArray[index]);
    }
  }

  hideSalesPopup() {
    if (this) {
      this.removeAttribute('show');
      this.classList.remove(this.classUp);
      this.classList.add(this.classDown);
    }
  }
  showSalesPopup() {
    if (this) {
      this.setAttribute('show', '');
      this.classList.add(this.classUp);
      this.classList.remove(this.classDown);
    }
  }
  setupEvents() {
    if (this.pauseOnHover) {
      this.addEventListener('mouseenter', (e) => {
        this.mouseenterHandler(e);
      });
      this.addEventListener('mouseleave', () => {
        this.mouseleaveHandler();
      });
    }
    if (this.close_btn) {
      this.close_btn.addEventListener('click', (e) => {
        e.preventDefault();
        this.hideSalesPopup();
        this.clearEvents();
        setTimeout(() => {
          this.remove();
        }, 1000);
      });
    }
  }
  mouseenterHandler() {
    if (this.resetOnHover) {
      if (this.progressbar) {
        this.progressbar.style.setProperty('animation-name', 'none');
      }
    } else {
      this.time.REMAINING = this.time.END - new Date().getTime();
      // console.log(this.time.REMAINING);
    }
    clearTimeout(this.stayTimeout);
  }
  mouseleaveHandler() {
    if (this.resetOnHover) {
      this.time.REMAINING = this.stayTime;
      if (this.progressbar) {
        this.progressbar.style.setProperty('animation-name', 'hdt-ani-w');
      }
    } else {
      this.time.END = new Date().getTime() + this.time.REMAINING;
    }
    this.stayTimeout = setTimeout(() => {
      this.unloadSalesPopup();
      this.hideSalesPopup();
    }, this.time.REMAINING);
  }

  clearEvents() {
    this.removeEventListener('mouseenter', this.mouseenterHandler);
    this.removeEventListener('mouseleave', this.mouseleaveHandler);
    clearTimeout(this.stayTimeout);
    clearTimeout(this.starTimeout);
  }
  // unload sales popup
  unloadSalesPopup() {
    // this.hideSalesPopup();
    this.starTimeout = setTimeout(() => {
      // if(this) this.remove();
      this.showSalesPopup();
      this.loadSalesPopup();
    }, this.startTime);
  }

  startProgressbar() {
    if (this.progressbar) {
      this.progressbar.style.setProperty('animation-iteration-count', 'infinite');
    }
  }
  stopProgressbar() {
    if (this.progressbar) {
      this.progressbar.style.removeProperty('animation-iteration-count');
    }
  }
  // load sales popup
  loadSalesPopup() {
    // document.body.appendChild(this);
    this.removeAttribute('hidden');
    if (this.ppType == '1') {
      this.updateData(this.index);
      ++this.index;
      if (this.index > this.max) {
        this.index = 0;
      }
    } else {
      this.updateData(this.getRandomInit(this.min, this.max));
    }

    this.time.START = new Date().getTime();
    this.time.END = this.time.START + this.stayTime;

    this.stayTimeout = setTimeout(() => {
      clearTimeout(this.stayTimeout);
      this.unloadSalesPopup();
      this.hideSalesPopup();
    }, this.stayTime);
    // this.stopProgressbar();
  }
}

customElements.define('hdt-sales-popup', SalesPopup);

class ageVerificationModal extends HTMLElement {
  constructor() {
    super();
    this.configs = JSON.parse(this.getAttribute('configs'));
    if (!Shopify.designMode && getCookie("theme4:age-verify:" + this.configs.id) === 'verified') return;

    this.modal = this.querySelector('hdt-modal');
    this.dialog = this.querySelector('dialog');

    if (Shopify.designMode) {
      this._shopifySection = this._shopifySection || this.closest('.shopify-section');
      this._shopifySection.addEventListener('shopify:section:load', () => this.showModal());
      // this._shopifySection.addEventListener('shopify:section:select', () => this.showModal());
      // this._shopifySection.addEventListener('shopify:section:deselect', () => this.modal.close());
    }
  }

  connectedCallback() {
    if (Shopify.designMode) return;
    if (getCookie("theme4:age-verify:" + this.configs.id) === 'verified') return;

    this.addEventListener('click', (e) => {
      const el = e.target.closest('[data-action]');
      if (!el) return;
      const action = el.getAttribute('data-action');
      if (action === 'verify') { e.preventDefault(); e.stopPropagation(); this.verifyAge(); }
      if (action === 'exit') { e.preventDefault(); e.stopPropagation(); this.exitSite(); }
    }, { capture: true });

    if (this.dialog) {
      this.allowBackdropClose = false;
      this.dialog.addEventListener(`${dialogClose}`, () => {
        if (this.allowBackdropClose) this.hideModal();
      });
      this.dialog.addEventListener('close', () => {
        if (!this.allowBackdropClose) this.modal && this.modal.open && this.modal.open();
      });
      this.dialog.addEventListener('cancel', (e) => {
        if (!this.allowBackdropClose) {
          e.preventDefault();
          e.stopPropagation();
          this.exitSite();
        }
      });
    }

    // const mode = this.configs.show_on;
    // if (mode === 'page_load') this.showModalWithDelay();
    // else if (mode === 'scroll') this.setupScrollListener();
    // else if (mode === 'mouse_leave') this.setupMouseLeaveListener();
    this.showModalWithDelay()
  }

  showModalWithDelay() { setTimeout(() => this.showModal(), this.configs.time_delay * 1000); }

  setupScrollListener() {
    const fnShow = this.showModal.bind(this);
    const docHeight = document.documentElement.scrollHeight - document.documentElement.clientHeight - 500;
    const onScroll = () => {
      if (window.scrollY >= docHeight) { fnShow(); window.removeEventListener('scroll', onScroll); }
    };
    window.addEventListener('scroll', onScroll);
  }

  setupMouseLeaveListener() {
    const fnShow = this.showModal.bind(this);
    document.querySelector('body').addEventListener('mouseleave', fnShow);
  }

  showModal() { this.modal.open(); }
  hideModal() { this.modal.close(); }

  verifyAge() {
    if (this.configs.date_of_birth) {
      const formRoot = (this.dialog || this).querySelector('.hdt-age-verify_content') || (this.dialog || this);
      const monthEl = formRoot.querySelector('#agemonth');
      const dayEl = formRoot.querySelector('#ageday');
      const yearEl = formRoot.querySelector('#ageyear');

      const showError = (msg) => {
        let err = formRoot.querySelector('.hdt-age-error');
        if (!err) {
          err = document.createElement('div');
          err.className = 'hdt-age-error';
          err.style.cssText = 'color:#ef4444;margin-top:12px;font-size:13px;';
          const formWrap = formRoot.querySelector('.hdt-age-verify-form') || formRoot.querySelector('.hdt-content');
          if (formWrap) formWrap.insertAdjacentElement('afterend', err);
          else formRoot.appendChild(err);
        }
        err.textContent = msg;
        err.style.display = '';
      };
      const clearError = () => {
        const err = formRoot.querySelector('.hdt-age-error');
        if (err) { err.textContent = ''; err.style.display = 'none'; }
      };

      if (!monthEl || !dayEl || !yearEl) {
        showError('Please select your full date of birth.');
        return;
      }
      if (monthEl.selectedIndex === 0 || dayEl.selectedIndex === 0 || yearEl.selectedIndex === 0) {
        showError('Please select your full date of birth.');
        return;
      }

      const m = parseInt(monthEl.value, 10);
      const d = parseInt(dayEl.value, 10);
      const y = parseInt(yearEl.value, 10);

      // Validate ngày hợp lệ
      const birth = new Date(y, m - 1, d);
      if (
        !Number.isFinite(m) || !Number.isFinite(d) || !Number.isFinite(y) ||
        birth.getFullYear() !== y || birth.getMonth() !== (m - 1) || birth.getDate() !== d
      ) {
        showError('Please select your full date of birth.');
        return;
      }

      const today = new Date();
      const threshold = new Date(y + this.configs.age_limit, m - 1, d);
      if (today < threshold) {
        showError(`You must be at least ${this.configs.age_limit} years old to access this website.`);
        return;
      }
      clearError();
    }

    const cookieDays = Number.parseInt(this.configs.day_next_show) > 0
      ? Number.parseInt(this.configs.day_next_show)
      : Number.parseInt(this.configs.day_next);
    setCookie("theme4:age-verify:" + this.configs.id, 'verified', cookieDays);
    if (this._preventEscHandler) {
      document.removeEventListener('keydown', this._preventEscHandler, true);
      this._preventEscHandler = null;
    }
    if (this._reopenOnClose) {
      this.dialog && this.dialog.removeEventListener('close', this._reopenOnClose, { once: true });
      this._reopenOnClose = null;
    }
    if (this._blockOutsideClick) {
      document.removeEventListener('click', this._blockOutsideClick, true);
      this._blockOutsideClick = null;
    }
    if (this._blockMouseHandlers && Array.isArray(this._blockMouseHandlers)) {
      this._blockMouseHandlers.forEach(({ type, handler }) => {
        document.removeEventListener(type, handler, true);
      });
      this._blockMouseHandlers = null;
    }
    this.allowBackdropClose = true;
    this.hideModal();
  }

  exitSite() {
    const scope = this.dialog || this;
    const root = scope.querySelector('.hdt-age-verify_content') || scope;
    const headingEl = root.querySelector('h2');
    let descEl = root.querySelector('.hdt-text-base') || root.querySelector('p');
    const form = root.querySelector('.hdt-age-verify-form');
    const closeBtn = scope.querySelector('[ref="closeButton"]') || scope.querySelector('.hdt-dialog-btn__close');

    if (headingEl) headingEl.textContent = 'Access forbidden';
    if (!descEl) {
      descEl = document.createElement('div');
      descEl.style.marginBottom = '1.5rem';
      const container = root.querySelector('.hdt-content') || root;
      container.insertBefore(descEl, form || container.firstChild);
    }
    descEl.textContent = 'Your access is restricted because of your age.';
    if (form) form.style.display = 'none';
    if (closeBtn) { closeBtn.setAttribute('disabled', 'true'); closeBtn.style.display = 'none'; }

    if (!this._preventEscHandler) {
      this._preventEscHandler = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); } };
      document.addEventListener('keydown', this._preventEscHandler, true);
    }

    if (!this._blockOutsideClick) {
      this._blockOutsideClick = (e) => { if (this.dialog && !this.dialog.contains(e.target)) { e.preventDefault(); e.stopPropagation(); } };
      document.addEventListener('click', this._blockOutsideClick, true);
    }

    if (!this._blockMouseHandlers) {
      this._blockMouseHandlers = [];
      const types = [
        'click', 'mousedown', 'mouseup', 'mousemove', 'mouseover', 'mouseout',
        'contextmenu', 'wheel', 'scroll',
        'touchstart', 'touchmove', 'touchend',
        'pointerdown', 'pointermove', 'pointerup'
      ];
      types.forEach((type) => {
        const handler = (e) => {
          e.preventDefault();
          e.stopPropagation();
        };
        document.addEventListener(type, handler, true);
        this._blockMouseHandlers.push({ type, handler });
      });
    }

    if (this.dialog && this.modal && !this._reopenOnClose) {
      this._reopenOnClose = () => { this.modal.open && this.modal.open(); };
      this.dialog.addEventListener('close', this._reopenOnClose, { once: true });
    }
  }

}

customElements.define('sys-age-verify', ageVerificationModal);


// ===============================
//        Quick Order List
// ===============================

class BulkAdd extends HTMLElement {
  static ASYNC_REQUEST_DELAY = 300;

  constructor() {
    super();
    this.queue = [];
    this.setRequestStarted(false)
    this.ids = [];
  }
  startQueue(id, quantity) {
    this.queue.push({ id, quantity });

    const interval = setInterval(() => {
      if (this.queue.length > 0) {
        if (!this.requestStarted) {
          this.sendRequest(this.queue);
        }
      } else {
        clearInterval(interval);
      }
    }, BulkAdd.ASYNC_REQUEST_DELAY);
  }

  sendRequest(queue) {
    this.setRequestStarted(true);
    const items = {};
    const ids = [];

    queue.forEach((queueItem) => {
      ids.push(queueItem.id);
      items[parseInt(queueItem.id)] = queueItem.quantity;
    });
    this.queue = this.queue.filter((queueElement) => !queue.includes(queueElement));

    this.updateMultipleQty(items,ids);
  }

  setRequestStarted(requestStarted) {
    this._requestStarted = requestStarted;
  }

  get requestStarted() {
    return this._requestStarted;
  }

}
class QuickOrderList extends BulkAdd {

  hasPendingQuantityUpdate = false;
  constructor() {
    super();
    this.quickOrderListId = '#' + this.id;
    this.sectionId = this.dataset.sectionId;

    const debouncedOnChange = debounce((event) => {
      this.onChange(event);
    }, BulkAdd.ASYNC_REQUEST_DELAY);

    this.addEventListener('change', debouncedOnChange.bind(this));
  }
  onSubmit(event) {
    event.preventDefault();
  }

  connectedCallback() {
    document.addEventListener($4('hdt-cart-drawer') ? cartUpdate : 'variant:add', this.fetchQuickOrder.bind(this) );
  }
  disconnectedCallback() {
    document.removeEventListener($4('hdt-cart-drawer') ? cartUpdate : 'variant:add', this.fetchQuickOrder.bind(this) );
  }
  async fetchQuickOrder() {
    const section_data = await fetch(`${window.location.pathname}?section_id=${this.sectionId}`).then(r => r.text());
    const html = new DOMParser().parseFromString(section_data, 'text/html');
    const sourceQty = html.querySelector(this.quickOrderListId);
    $4('form#QuickOrderList', this).removeEventListener('submit', this.onSubmit.bind(this));
    this.innerHTML = sourceQty.innerHTML;
    // this.scrollIntoView({
    //   behavior: "smooth",
    //   block: "start",
    // })
  }
  onChange(event) {
    const inputValue = parseInt(event.target.value);
    if (inputValue >= 0) {
      event.target.setAttribute('value', inputValue);
      this.startQueue(event.target.dataset.quantityVariantId, inputValue);
    } else {
      this.resetQuantityInput(event.target.dataset.quantityVariantId);
    }
  }
  onLoading(id) {
    // this.classList.add('is-fetching');
    $4(`#Variant-${id}`, this)?.classList.add('is-fetching');
    $4(`#Variant-${id} [price_loading]`, this)?.setAttribute('aria-busy', true);
    $$4('#hdt-quick-order-list-total .hdt-btn-loading__svg', this).forEach(el => el.setAttribute('aria-busy', true));
  }
  deLoading(id) {
    $4(`#Variant-${id} [price_loading]`, this)?.setAttribute('aria-busy', false);
    $$4('#hdt-quick-order-list-total .hdt-btn-loading__svg', this).forEach(el => el.setAttribute('aria-busy', false));
    // this.classList.remove('is-fetching');
    $4(`#Variant-${id}`, this)?.classList.remove('is-fetching');
  }
  fetchConfig(type = 'json') {
    return {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: `application/${type}` },
    };
  }
  // update quantity product
  updateMultipleQty(items,ids = [], is_remove_all = false) {
    if (this.queue.length == 0) this.hasPendingQuantityUpdate = false;
    const url = this.dataset.url || window.location.pathname;
    const bulkSectionRender = [this.sectionId];
    const page = this.dataset.currentPage || 1;
    let body = JSON.stringify({
      updates: items,
      sections: bulkSectionRender,
      sections_url: `${url}?page=${page}`,
    });
    this.onLoading(ids[0]);
    document.dispatchEvent(new CustomEvent("theme:loading:doing",{bubbles:!0}));
    fetch(`${Shopify.routes.root}cart/update.js`, { ...this.fetchConfig(), ...{ body } })
    .then((response) => response.text())
    .then(async (state) => {
      const parsedState = JSON.parse(state);
      const html_data = parsedState.sections[this.sectionId];
      const html_parse = new DOMParser().parseFromString(html_data, 'text/html');
      // console.log(html_parse)
      if(!is_remove_all){
        this.updateLineVariant(ids, html_parse);
        this.updateTotal(html_parse);
      }else {
        this.updateAll(html_parse)
      }
    })
    .catch((e) => {
      console.error(e);
    })
    .finally(() => {
      document.dispatchEvent(new CustomEvent("theme:loading:done",{bubbles:!0}));
      this.deLoading(ids[0]);
      document.dispatchEvent(new CustomEvent(cartReload));
      document.dispatchEvent(new CustomEvent(currencyUpdate));
      this.setRequestStarted(false);
    });
  }
  // Update content
  updateLineVariant(ids,html_parse){
    ids.forEach((id) => {
      let variant_html = html_parse.querySelector(`#Variant-${id}`);
      $4(`#Variant-${id}`, this)?.replaceWith(variant_html);
    });
  }
  updateTotal(html_parse){
    const total_html = html_parse.querySelector('#hdt-quick-order-list-total');
    this.querySelector('#hdt-quick-order-list-total').replaceWith(total_html);
  }
  updateAll(html_parse){
    const all_html = html_parse.querySelector('hdt-quick-order-list');
    this.innerHTML = all_html.innerHTML;
    this.scrollIntoView({
      behavior: "smooth",
      block: "start",
    })
  }
  // Message erro
  updateError(variant_id,message) {
    this.updateLiveRegions(variant_id, message);
  }
  updateLiveRegions(variant_id, message) {
    const variantItemError = $4(`#Variant-${variant_id}`, this);
    if (variantItemError) {
      $4('.hdt-error-message-text', variantItemError).innerHTML = message;
      $4('[data-error-message]', variantItemError).removeAttribute('hidden');
    }
  }
  resetQuantityInput(id){
    const quantityElement = document.getElementById(`Quantity-${id}`);
    quantityElement.value = quantityElement.getAttribute('value');
  }
  get cartVariantsForProduct() {
    return JSON.parse(this.querySelector('[data-cart-contents]')?.innerHTML || '[]');
  }
}
customElements.define('hdt-quick-order-list', QuickOrderList);

// remove variant in cart
class QuickOrderListRemoveButton extends HTMLElement {
  constructor() {
    super();
    this.addEventListener('click', (event) => {
      event.preventDefault();
      const quickOrderList = this.closest('hdt-quick-order-list');
      quickOrderList.updateMultipleQty({[this.dataset.index]: 0}, [this.dataset.index]);
    });
  }
}
customElements.define('hdt-quick-order-list-remove-button', QuickOrderListRemoveButton);

// remove all variant in cart
class QuickOrderListRemoveAllButton extends HTMLElement {
  constructor() {
    super();

  }
  connectedCallback(){
    this.quickOrderList = this.closest('hdt-quick-order-list');
    this.addEventListener('click', () => {
      const items = this.quickOrderList.cartVariantsForProduct.reduce(
        (acc, variantId) => ({ ...acc, [variantId]: 0 }),
        {}
      );
      this.quickOrderList.updateMultipleQty(items,[], true);
    })
  }
}
customElements.define('hdt-quick-order-list-remove-all-button', QuickOrderListRemoveAllButton);

// ================================
// Toast Notification System
// ================================

class ToastNotification {
  constructor() {
    this.container = null;
    this.init();
  }

  init() {
    // Create toast container if it doesn't exist
    if (!document.querySelector('.toast-container')) {
      this.container = document.createElement('div');
      this.container.className = 'toast-container';
      document.body.appendChild(this.container);
    } else {
      this.container = document.querySelector('.toast-container');
    }
  }

  show(message, type = 'info', title = 'Notification', duration = 5000) {
    const toast = this.createToast(message, type, title);
    this.container.appendChild(toast);

    // Trigger animation
    setTimeout(() => {
      toast.classList.add('show');
    }, 10);

    // Auto remove after duration
    if (duration > 0) {
      setTimeout(() => {
        this.hide(toast);
      }, duration);
    }

    return toast;
  }

  createToast(message, type, title) {
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    
    toast.innerHTML = `
      <div class="toast-header">
        <div class="toast-icon ${type}">${this.getIcon(type)}</div>
        <div class="toast-title">${title}</div>
        <button type="button" class="toast-close" aria-label="Close">&times;</button>
      </div>
      <div class="toast-body">${message}</div>
    `;

    // Add close functionality
    const closeBtn = toast.querySelector('.toast-close');
    closeBtn.addEventListener('click', () => {
      this.hide(toast);
    });

    return toast;
  }

  hide(toast) {
    toast.classList.add('hide');
    setTimeout(() => {
      if (toast.parentNode) {
        toast.parentNode.removeChild(toast);
      }
    }, 300);
  }

  getIcon(type) {
    const icons = {
      error: '!',
      success: '✓',
      warning: '!',
      info: 'i'
    };
    return icons[type] || icons.info;
  }

  // Static methods for easy use
  static success(message, title = 'Success') {
    return new ToastNotification().show(message, 'success', title);
  }

  static error(message, title = 'Error') {
    return new ToastNotification().show(message, 'error', title);
  }

  static warning(message, title = 'Warning') {
    return new ToastNotification().show(message, 'warning', title);
  }

  static info(message, title = 'Info') {
    return new ToastNotification().show(message, 'info', title);
  }
}

// Initialize toast notification system
const toast = new ToastNotification();

window.addEventListener('cart:error', (event) => {
  
  // Extract error message from event
  let errorMessage = window.themeHDN.extras.cart.error_message;
  if (event.detail && event.detail.data.message) {
    errorMessage = event.detail.data.message;
  } else if (event.detail && event.detail.data.error) {
    errorMessage = event.detail.data.error;
  } else if (typeof event.detail === 'string') {
    errorMessage = event.detail;
  }
  
  // Show error toast
  ToastNotification.error(errorMessage, window.themeHDN.extras.cart.toast_title);
});

// ================================
//     Cart add Confetti
// ================================
class ConfettiElement extends HTMLElement {
  constructor() {
      super();
      
      // Globals
      this.canvas = null;
      this.ctx = null;
      this.W = 0;
      this.H = 0;
      this.mp = 150; // max particles
      this.particles = [];
      this.angle = 0;
      this.tiltAngle = 0;
      this.confettiActive = true;
      this.animationComplete = true;
      this.deactivationTimerHandler = null;
      this.reactivationTimerHandler = null;
      this.animationHandler = null;

      this.whenShow = null;
      this.hideAfterShow = null;
      this.isShow = [];
      
      // Particle colors
      this.particleColors = {
          colorOptions: ["DodgerBlue", "OliveDrab", "Gold", "pink", "SlateBlue", "lightblue", "Violet", "PaleGreen", "SteelBlue", "SandyBrown", "Chocolate", "Crimson"],
          colorIndex: 0,
          colorIncrementer: 0,
          colorThreshold: 10,
          getColor: function () {
              if (this.colorIncrementer >= 10) {
                  this.colorIncrementer = 0;
                  this.colorIndex++;
                  if (this.colorIndex >= this.colorOptions.length) {
                      this.colorIndex = 0;
                  }
              }
              this.colorIncrementer++;
              return this.colorOptions[this.colorIndex];
          }
      };
      
      // Bind methods
      this.handleResize = this.handleResize.bind(this);
  }
  
  connectedCallback() {
      this.init();
      this.setupEventListeners();
  }
  
  disconnectedCallback() {
      this.cleanup();
      this.removeEventListeners();
  }
  
  // Confetti Particle Factory
  createConfettiParticle(color) {
      const ctx = this.ctx;
      const W = this.W;
      const H = this.H;
      const mp = this.mp;
      
      return {
          x: Math.random() * W,
          y: (Math.random() * H) - H,
          r: this.randomFromTo(10, 30),
          d: (Math.random() * mp) + 10,
          color: color,
          tilt: Math.floor(Math.random() * 10) - 10,
          tiltAngleIncremental: (Math.random() * 0.07) + 0.05,
          tiltAngle: 0,
          
          draw: function() {
              ctx.beginPath();
              ctx.lineWidth = this.r / 2;
              ctx.strokeStyle = this.color;
              ctx.moveTo(this.x + this.tilt + (this.r / 4), this.y);
              ctx.lineTo(this.x + this.tilt, this.y + this.tilt + (this.r / 4));
              return ctx.stroke();
          }
      };
  }
  
  init() {
    this.setGlobals();
    // Add resize listener
    window.addEventListener('resize', this.handleResize);
  }
  
  setupEventListeners() {
    // Listen for custom events
    this.handleConfettiStart = this.handleConfettiStart.bind(this);
    this.handleConfettiPause = this.handleConfettiPause.bind(this);
    
    document.addEventListener('confetti:start', this.handleConfettiStart);
    document.addEventListener('confetti:pause', this.handleConfettiPause);

    const cartDrawer = document.querySelector('#CartDrawer');
    cartDrawer?.addEventListener(dialogClose,()=> {
      this.pause();
    })

    document.addEventListener(progressBarChange, (event)=> {
      this.handleProgressBarChange(event);

    })
  }
  
  removeEventListeners() {
    document.removeEventListener('confetti:start', this.handleConfettiStart);
    document.removeEventListener('confetti:pause', this.handleConfettiPause);
    const cartDrawer = document.querySelector('#CartDrawer');
    cartDrawer.removeEventListener(dialogClose,()=> {
      this.pause();
    })
  }

  handleProgressBarChange(event){
    clearTimeout(this.whenShow);
    clearTimeout(this.hideAfterShow);
    if(this.isShow.length == 1 && parseInt(event.detail.rangeValue) == 1){
      this.handlePauseAnimation();
      return;
    }
    if(parseInt(event.detail.rangeValue) == 1 && this.isShow.length <= 1 ){
      this.showPopover();
      this.start();
      this.isShow.push(event.detail.rangeValue);
    }else{
      this.isShow.pop(1);
    }
    this.handlePauseAnimation();
    // console.log(this.isShow);
  }
  handlePauseAnimation(){
    this.whenShow = setTimeout(() => {
      this.pause();
      this.hideAfterShow = setTimeout(() => {
        this.hidePopover();
      }, 5000);
    }, 3000);
  }
  handleConfettiStart(event) {
      // Check if this specific element should respond to the event
    if (event.detail && event.detail.target && event.detail.target !== this) {
        return; // Ignore if targeted at another element
    }
    this.showPopover();
    this.start();
  }
  
  handleConfettiPause(event) {
    clearTimeout(this.whenShow);
    clearTimeout(this.hideAfterShow);
      // Check if this specific element should respond to the event
    if (event.detail && event.detail.target && event.detail.target !== this) {
        return; // Ignore if targeted at another element
    }
    this.pause();
    
    this.hideAfterShow = setTimeout(() => {
      this.hidePopover();
    }, 5000);
  }
  
  cleanup() {
    window.removeEventListener('resize', this.handleResize);
    this.removeEventListeners();
    this.clearTimers();
    this.stopConfetti();
    if (this.hideTimeout) {
      clearTimeout(this.hideTimeout);
    }
  }
  
  handleResize() {
    this.W = window.innerWidth;
    this.H = window.innerHeight;
    if (this.canvas) {
        this.canvas.width = this.W;
        this.canvas.height = this.H;
    }
  }

  setGlobals() {
    // Create canvas if it doesn't exist
    let canvas = this.querySelector('#confettiCanvas');
    if (!canvas) {
        canvas = document.createElement('canvas');
        canvas.id = 'confettiCanvas';
        canvas.style.cssText = 'position: fixed; top: 0; left: 0; display: none; z-index: 9999; pointer-events: none;';
        this.appendChild(canvas);
    }
    
    this.canvas = canvas;
    this.ctx = this.canvas.getContext('2d');
    this.W = window.innerWidth;
    this.H = window.innerHeight;
    this.canvas.width = this.W;
    this.canvas.height = this.H;
  }
  
  initializeConfetti() {
    if (!this.canvas || !this.ctx) {
        console.error('Canvas not initialized');
        return;
    }
    
    // Ngừng animation hiện tại trước khi bắt đầu cái mới
    this.clearTimers();
    
    this.canvas.style.display = 'block';
    this.particles = [];
    this.animationComplete = false;
    this.confettiActive = true;
    
    for (let i = 0; i < this.mp; i++) {
        const particleColor = this.particleColors.getColor();
        this.particles.push(this.createConfettiParticle(particleColor));
    }
    
    this.startConfetti();
  }
  
  draw() {
    if (!this.ctx) return [];
    
    this.ctx.clearRect(0, 0, this.W, this.H);
    const results = [];
    
    for (let i = 0; i < this.mp && i < this.particles.length; i++) {
        if (this.particles[i] && this.particles[i].draw) {
            results.push(this.particles[i].draw());
        }
    }
    
    this.update();
    return results;
  }
  
  randomFromTo(from, to) {
    return Math.floor(Math.random() * (to - from + 1) + from);
  }
  
  update() {
    let remainingFlakes = 0;
    let particle;
    this.angle += 0.01;
    this.tiltAngle += 0.1;
    
    for (let i = 0; i < this.mp && i < this.particles.length; i++) {
        particle = this.particles[i];
        if (this.animationComplete) return;
        
        if (!this.confettiActive && particle.y < -15) {
            particle.y = this.H + 100;
            continue;
        }
        
        this.stepParticle(particle, i);
        
        if (particle.y <= this.H) {
            remainingFlakes++;
        }
        
        this.checkForReposition(particle, i);
    }
    
    if (remainingFlakes === 0) {
        this.stopConfetti();
    }
  }
  
  checkForReposition(particle, index) {
    if ((particle.x > this.W + 20 || particle.x < -20 || particle.y > this.H) && this.confettiActive) {
      if (index % 5 > 0 || index % 2 === 0) { // 66.67% of the flakes
          this.repositionParticle(particle, Math.random() * this.W, -10, Math.floor(Math.random() * 10) - 10);
      } else {
        if (Math.sin(this.angle) > 0) {
            // Enter from the left
            this.repositionParticle(particle, -5, Math.random() * this.H, Math.floor(Math.random() * 10) - 10);
        } else {
            // Enter from the right
            this.repositionParticle(particle, this.W + 5, Math.random() * this.H, Math.floor(Math.random() * 10) - 10);
        }
      }
    }
  }
  
  stepParticle(particle, particleIndex) {
    particle.tiltAngle += particle.tiltAngleIncremental;
    particle.y += (Math.cos(this.angle + particle.d) + 3 + particle.r / 2) / 2;
    particle.x += Math.sin(this.angle);
    particle.tilt = (Math.sin(particle.tiltAngle - (particleIndex / 3))) * 15;
  }
  
  repositionParticle(particle, xCoordinate, yCoordinate, tilt) {
    particle.x = xCoordinate;
    particle.y = yCoordinate;
    particle.tilt = tilt;
  }
  
  startConfetti() {
    // Đảm bảo chỉ có 1 animation loop chạy
    if (this.animationHandler) {
      cancelAnimationFrame(this.animationHandler);
      this.animationHandler = null;
    }
    
    this.W = window.innerWidth;
    this.H = window.innerHeight;
    if (this.canvas) {
      this.canvas.width = this.W;
      this.canvas.height = this.H;
    }
    
    const animloop = () => {
      if (this.animationComplete) return null;
      this.animationHandler = requestAnimationFrame(animloop);
      return this.draw();
    };
    
    animloop();
  }
  
  clearTimers() {
    if (this.reactivationTimerHandler) {
      clearTimeout(this.reactivationTimerHandler);
    }
    if (this.animationHandler) {
      cancelAnimationFrame(this.animationHandler);
      this.animationHandler = null;
    }
  }
  
  deactivateConfetti() {
    this.confettiActive = false;
  }
  
  stopConfetti() {
    this.animationComplete = true;
    if (this.ctx) {
        this.ctx.clearRect(0, 0, this.W, this.H);
    }
    if (this.canvas) {
        this.canvas.style.display = 'none';
    }
  }
  
  restartConfetti() {
    this.clearTimers();
    this.stopConfetti();
    this.reactivationTimerHandler = setTimeout(() => {
      this.confettiActive = true;
      this.animationComplete = false;
      this.initializeConfetti();
    }, 100);
  }
  
  forceStopConfetti() {
    this.clearTimers();
    this.stopConfetti();
  }

  
  // Public API methods
  start() {
    // Chỉ start nếu chưa có animation đang chạy
    if (this.animationComplete || !this.confettiActive) {
      this.initializeConfetti();
    }
  }
  
  pause() {
    this.deactivateConfetti();
  }
  
  stop() {
    this.forceStopConfetti();
  }
  
  restart() {
    this.restartConfetti();
  }
}

// Define the custom element
customElements.define('confetti-element', ConfettiElement);

// ================================
//     Add Gift Card 
// ================================

// DEFINE state:
//   0: no-fetch 
//   1: added 
//   2: removed
class AddGiftCard extends HTMLElement {
  constructor() {
    super();
    this.layout_id = this.getAttribute('aria-controls');
    this.layout = document.querySelector(`${this.layout_id}`);
    this.sectionId = this.getAttribute('data-section-id');
    this.state = sessionStorage.getItem('hdt-add-gift-card-state') || 0;
  }
  get variantID(){
    return this.getAttribute('data-variant-id');
  }
  get totalRequired(){
    return parseFloat(this.getAttribute('data-total-required'));
  }
  get currentPrice(){
    return parseFloat(this.getAttribute('data-current-price'));
  }
  connectedCallback(){
    // console.log(this.totalRequired, this.currentPrice);
    // console.log(this.state);
    this.fetchData();
  }
  fetchData(){
    if (this.currentPrice >= this.totalRequired && this.state == 0){
      // console.log("ADD gift card")
      this.updateCart(this.variantID, 1);
      sessionStorage.setItem('hdt-add-gift-card-state', 1);
    }else if(this.currentPrice < this.totalRequired && this.state == 1){
      // this.updateCart(this.variantID, 0);
      // console.log("REomve gift card")
      this.updateCart(this.variantID, 0);
      sessionStorage.setItem('hdt-add-gift-card-state', 2);
    }else if( this.currentPrice >= this.totalRequired && this.state == 2){
      // this.updateCart(this.variantID, 1);
      // console.log("ADD gift card")
      this.updateCart(this.variantID, 1);
      sessionStorage.setItem('hdt-add-gift-card-state', 1);
    }
  }
  fetchConfig(type = 'json') {
    return {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: `application/${type}` },
    };
  }
  updateCart(id, quantity){

    const body = JSON.stringify({
      updates: {
        [id]: quantity
      },
      sections: [this.sectionId],
      sections_url: `${window.location.pathname}?section_id=${this.sectionId}`
    }); 
    fetch(`${Shopify.routes.root}cart/update.js`, { ...this.fetchConfig(), ...{ body } })
    .then((response) => response.text())
    .then(async (state) => {
      const parsedState = JSON.parse(state);
      const html_data = parsedState.sections[this.sectionId];
      const html_parse = new DOMParser().parseFromString(html_data, 'text/html');
      const layout_data = html_parse.querySelector(`${this.layout_id}`);
      if(layout_data){
        this.layout?.replaceWith(layout_data);
      }
    })
    .catch((e) => {
      console.error(e);
    })
    .finally(() => {

    });

  }
}

customElements.define('hdt-add-gift-card', AddGiftCard);

// ================================
//     Shipping Protection
// ================================
class ShippingProtection extends HTMLElement {
  constructor() {
    super();
    this.STATE = {
      ADD: 'add',
      REMOVE: 'remove',
    };
    // this.cartAction = cartUpdate;
    this.updateCurrency = currencyUpdate;
    this.ASYNC_REQUEST_DELAY = 300;
    this.cartItemsComponent = this.closest(`${this.dataPageId}`);
  }
  get toggleCheckBox(){
    return this.querySelector('input[name="shipping_protection"]');
  }
  get protectId(){
    return this.querySelector('input[name="shipping_protect_id"]').value;
  }
  get sectionId(){
    return this.getAttribute('section-id');
  }
  get shippingProtectionUpdate(){
    return this.closest(`#shopify-section-${this.sectionId}`).querySelector('[shipping-protection-update]');
  }
  get dataPageId(){
    return this.getAttribute('data-page-id');
  }
  connectedCallback(){
    this.debounceChange = debounce((e) => {
      this.handleChange(e);
    }, this.ASYNC_REQUEST_DELAY);
    this.toggleCheckBox.addEventListener('change', this.debounceChange.bind(this));
    // this.syncCartUpdate();
  }
  disconnectCallback(){
    this.toggleCheckBox.removeEventListener('change', this.debounceChange.bind(this));
  }
  handleChange(event){
    if(event.target.checked){
      this.protectAction(this.STATE.ADD);
    }else{
      this.protectAction(this.STATE.REMOVE);
    }
  }
  protectAction(action){ 
    if(action == this.STATE.ADD){
      this.updateCart(this.protectId, 1);
    }else if(action == this.STATE.REMOVE){
      this.updateCart(this.protectId, 0);
    }
  }
  fetchConfig(type = 'json'){
    return {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: `application/${type}` },
    };
  }
  async updateCart(productId, quantity){
    const body = JSON.stringify({
      updates: {
        [productId]: quantity
      },
      sections: [this.sectionId],
      sections_url: `${window.location.pathname}?section_id=${this.sectionId}`
    }); 
    document.dispatchEvent(new CustomEvent('theme:loading:doing', { bubbles: true }));
    this.cartItemsComponent.style.setProperty('pointer-events', 'none');
    this.cartItemsComponent.style.setProperty('opacity', '0.5');
    fetch(`${Shopify.routes.root}cart/update.js`, { ...this.fetchConfig(), ...{ body } })
    .then((response) => response.text())
    .then((state) => {
      // const parsedState = JSON.parse(state);
      // const sectionData = new DOMParser().parseFromString(parsedState.sections[this.sectionId], 'text/html');

      // const needUpdate = sectionData.querySelector('[shipping-protection-update]');
      // if(needUpdate){
      //   this.shippingProtectionUpdate?.replaceWith(needUpdate);
      // }

      // const shippingProtectWidget = sectionData.querySelector('shipping-protection');
      // if(shippingProtectWidget){
      //   this.replaceWith(shippingProtectWidget);
      // }


      document.dispatchEvent(new CustomEvent(cartReload, { bubbles: true }));
      
      document.dispatchEvent(new CustomEvent('theme:loading:done', { bubbles: true }));
    })
    .finally(() => {
      document.dispatchEvent(new CustomEvent(this.updateCurrency,{ bubbles: true }));
      this.cartItemsComponent.style.setProperty('pointer-events', 'auto');
      this.cartItemsComponent.style.setProperty('opacity', '1');
    })
  }
  syncCartUpdate(){
    document.addEventListener(cartUpdate, (event) => {
      try {
        const items_in_cart = event.detail.cartData.items;
        if(items_in_cart.length == 1 && items_in_cart[0].id == this.protectId){
          this.updateCart(this.protectId, 0);
        }
      } catch (err) {
        console.error(err);
      }
      
    });
  }
}
customElements.define('shipping-protection', ShippingProtection);

class AccordionGroup extends HTMLElement {
  #abortController;
  #boundHandleClick = this.handleClick.bind(this);
  #boundHandleResize = this.handleResize.bind(this);
  #resizeObserver;

  get singleOpen(){
    return this.hasAttribute('single-open');
  }

  get accordionListings(){
    return this.querySelectorAll('hdt-accordion');
  }

  get isTypeAccordion(){
    return this.classList.contains('hdt-type-tab-accordion_');
  }

  itemNotTarget(event){
    return Array.from(this.accordionListings).filter((accordion) => accordion !== event.target.closest('hdt-accordion'));
  }

  handleResponsiveAccordion() {
    const accordions = this.accordionListings;
    if (accordions.length === 0) return;

    const isMobile = window.innerWidth < 768;

    if (isMobile) {
      accordions.forEach((accordion, index) => {
        if (index === 0) {
          accordion.toggle(true);
        } else {
          accordion.toggle(false);
        }
      });
    } else {
      accordions.forEach((accordion) => {
        accordion.toggle(true);
      });
    }
  }

  handleResize() {
    if (this.isTypeAccordion) {
      this.handleResponsiveAccordion();
    }
  }

  connectedCallback() {
    this.#abortController = new AbortController();
    
    if(this.singleOpen) {
      this.addEventListener('click', this.#boundHandleClick, { signal: this.#abortController.signal });
    }

    if (this.isTypeAccordion) {
      this.handleResponsiveAccordion();
      
      window.addEventListener('resize', this.#boundHandleResize, { signal: this.#abortController.signal });
    }
  }

  handleClick(event){
    if(event.target.tagName === 'SUMMARY' || event.target.closest('summary')) {
      this.itemNotTarget(event).forEach((accordion) => {
        accordion.toggle(false);
      });
    } 
  }

  disconnectedCallback() {
    this.#abortController?.abort();
  }
}
customElements.define('hdt-accordion-group', AccordionGroup);

class ShopifyAccountWrapp extends HTMLElement {
  constructor() {
    super();
    this._handleClick = this._handleClick.bind(this);
  }

  connectedCallback() {
    this.addEventListener('click', this._handleClick);
    
    if (getComputedStyle(this).display === 'inline') {
      this.style.display = 'block'; 
    }
  }

  disconnectedCallback() {
    this.removeEventListener('click', this._handleClick);
  }

  _handleClick(event) {
    const shopifyAccount = this.querySelector('shopify-account');

    if (shopifyAccount && shopifyAccount.shadowRoot) {
      const innerButton = shopifyAccount.shadowRoot.querySelector('.account-button');

      if (innerButton) {
        if (event.composedPath()[0] !== innerButton) {
          innerButton.click();
        }
      }
    }
  }
}

customElements.define('shopify-account-wrapp', ShopifyAccountWrapp);