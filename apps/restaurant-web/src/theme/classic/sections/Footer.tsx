import type { WebsiteSite } from "../../../api/types";

/** Closing line: restaurant identity, the owner's note and the year. */
export function Footer({ site }: { site: WebsiteSite }) {
  const { profile, content } = site;
  const name = [profile.name, profile.branchName].filter(Boolean).join(" · ");
  return (
    <footer className="site-footer on-dark">
      <div className="shell site-footer__inner">
        <span className="site-footer__name">{name}</span>
        <span>© {new Date().getFullYear()}</span>
        {content.footerNote && (
          <span className="site-footer__note">{content.footerNote}</span>
        )}
      </div>
    </footer>
  );
}
