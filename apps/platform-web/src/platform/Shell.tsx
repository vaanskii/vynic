import { useState } from "react";
import {
  Buildings,
  CaretDown,
  ChartDonut,
  ClockCounterClockwise,
  DesktopTower,
  Globe,
  List,
  SignOut,
  SlidersHorizontal,
  SquaresFour,
  Storefront,
  X,
} from "@phosphor-icons/react";
import { NavLink, Outlet, useLocation } from "react-router-dom";
import vynicLogo from "../assets/vynic-logo.png";
import { useAuth } from "./auth";

const navigation = [
  { label: "Overview", to: "/", icon: SquaresFour, end: true },
  { label: "Organizations", to: "/organizations", icon: Buildings },
  { label: "Venues", to: "/venues", icon: Storefront },
];

const groups = [
  {
    label: "Product",
    items: [
      { label: "Plans", to: "/plans", icon: ChartDonut },
      { label: "Features", to: "/features", icon: SlidersHorizontal },
    ],
  },
  {
    label: "Infrastructure",
    items: [
      { label: "Devices", to: "/devices", icon: DesktopTower },
      { label: "Domains", to: "/domains", icon: Globe },
    ],
  },
  {
    label: "Activity",
    items: [{ label: "Audit log", to: "/audit", icon: ClockCounterClockwise }],
  },
];

export function Shell() {
  const { actor, logout } = useAuth();
  const [open, setOpen] = useState(false);
  const [accountOpen, setAccountOpen] = useState(false);
  const location = useLocation();

  const item = ({ label, to, icon: Icon, end }: (typeof navigation)[number]) => (
    <NavLink
      key={to}
      to={to}
      end={end}
      onClick={() => setOpen(false)}
      className={({ isActive }) => `platform-nav__item${isActive ? " is-active" : ""}`}
    >
      <Icon size={18} weight="duotone" />
      <span>{label}</span>
    </NavLink>
  );

  return (
    <div className="platform-shell">
      <aside className={`platform-sidebar${open ? " is-open" : ""}`}>
        <div className="platform-sidebar__top">
          <NavLink className="platform-brand" to="/" onClick={() => setOpen(false)}>
            <img src={vynicLogo} alt="" />
            <span>Vynic</span>
            <small>Platform</small>
          </NavLink>
          <button className="platform-icon-button platform-sidebar__close" onClick={() => setOpen(false)} aria-label="Close navigation">
            <X size={18} />
          </button>
        </div>
        <nav className="platform-nav" aria-label="Platform navigation">
          <div className="platform-nav__section">{navigation.map(item)}</div>
          {groups.map((group) => (
            <div className="platform-nav__section" key={group.label}>
              <p>{group.label}</p>
              {group.items.map(item)}
            </div>
          ))}
        </nav>
        <a className="platform-sidebar__product-link" href="/product">View product site</a>
      </aside>
      {open ? <button className="platform-sidebar__scrim" aria-label="Close navigation" onClick={() => setOpen(false)} /> : null}

      <div className="platform-shell__main">
        <header className="platform-topbar">
          <button className="platform-icon-button platform-menu-button" onClick={() => setOpen(true)} aria-label="Open navigation">
            <List size={20} />
          </button>
          <div className="platform-topbar__route">
            <span>Control plane</span>
            <strong>{routeLabel(location.pathname)}</strong>
          </div>
          <div className="platform-account">
            <button
              className="platform-account__button"
              type="button"
              onClick={() => setAccountOpen((value) => !value)}
              aria-expanded={accountOpen}
            >
              <span className="platform-avatar">{actor?.displayName.slice(0, 1).toUpperCase()}</span>
              <span><strong>{actor?.displayName}</strong><small>{actor?.role.replaceAll("_", " ")}</small></span>
              <CaretDown size={14} />
            </button>
            {accountOpen ? (
              <div className="platform-account__menu">
                <p>{actor?.email}</p>
                <button type="button" onClick={logout}><SignOut size={16} /> Sign out</button>
              </div>
            ) : null}
          </div>
        </header>
        <main className="platform-content"><Outlet /></main>
      </div>
    </div>
  );
}

function routeLabel(pathname: string) {
  const segment = pathname.split("/").filter(Boolean)[0];
  if (!segment) return "Overview";
  return segment.replace(/\b\w/g, (value) => value.toUpperCase());
}
