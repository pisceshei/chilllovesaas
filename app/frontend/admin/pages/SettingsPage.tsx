import { Languages, Link2 } from "lucide-react";
import { Link } from "react-router-dom";
import { Card } from "../components/Card";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";

/**
 * 設定索引（ML-4 起啟用）。目前實作完成的分區：語言（ML-4）、網址重導（包 36）；
 * 其餘分區隨各里程碑陸續掛上，不預先列出點不進去的項目（避免死連結）。
 */
export function SettingsPage() {
  const t = useT();
  return (
    <Page title={t("settings.title")}>
      <Card padded>
        <p className="cl-card-note">{t("settings.hint")}</p>
        <ul className="cl-settings-list">
          <li>
            <Link className="cl-settings-item" to="/admin/settings/languages">
              <Languages aria-hidden="true" size={18} />
              <span className="cl-settings-item__text">
                {t("settings.languages")}
                <small>{t("settings.languages.desc")}</small>
              </span>
            </Link>
          </li>
          <li>
            <Link className="cl-settings-item" to="/admin/settings/redirects">
              <Link2 aria-hidden="true" size={18} />
              <span className="cl-settings-item__text">
                {t("settings.redirects")}
                <small>{t("settings.redirects.desc")}</small>
              </span>
            </Link>
          </li>
        </ul>
      </Card>
    </Page>
  );
}
