// 本尊 shop-js（Sign in with Shop／Shop Pay 生態）loader 模組的對位：我方無 Shop 帳號生態，只保住 `Shopify.SignInWithShop.*` 呼叫契約。
const S = (window.Shopify = window.Shopify || {});
S.SignInWithShop = S.SignInWithShop || {};
S.SignInWithShop.initShopCartSync = S.SignInWithShop.initShopCartSync || function () {};
S.SignInWithShop.init = S.SignInWithShop.init || function () {};
export default {};
