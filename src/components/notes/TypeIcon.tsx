import { useEffect, useState } from "react";
import type { Icon } from "@tabler/icons-react";
import { Folder, FolderOpen } from "@/lib/icons";
import { tablerIconName } from "@/lib/type-icons";

let iconCatalog: Map<string, Icon> | null = null;
let iconCatalogPromise: Promise<Map<string, Icon>> | null = null;

function loadIconCatalog(): Promise<Map<string, Icon>> {
  iconCatalogPromise ??= import("@/lib/tabler-icon-catalog").then((catalog) => {
    iconCatalog = catalog.TABLER_ICONS_BY_NAME;
    return iconCatalog;
  });
  return iconCatalogPromise;
}

/** A type's custom Tabler icon, or the default folder glyph. */
export function TypeIcon({
  icon,
  open = false,
  size,
  className,
  style,
}: {
  icon?: string;
  open?: boolean;
  size: number;
  className?: string;
  style?: React.CSSProperties;
}) {
  const name = tablerIconName(icon);
  const [CustomIcon, setCustomIcon] = useState<Icon | null>(() =>
    name && iconCatalog ? iconCatalog.get(name) ?? null : null,
  );

  useEffect(() => {
    if (!name) {
      setCustomIcon(null);
      return;
    }
    const cached = iconCatalog?.get(name);
    if (cached) {
      setCustomIcon(() => cached);
      return;
    }
    let cancelled = false;
    void loadIconCatalog().then((catalog) => {
      if (!cancelled) setCustomIcon(() => catalog.get(name) ?? null);
    });
    return () => {
      cancelled = true;
    };
  }, [name]);

  if (CustomIcon) {
    return <CustomIcon size={size} className={className} style={style} aria-hidden="true" />;
  }
  const Fallback = open ? FolderOpen : Folder;
  return <Fallback size={size} className={className} style={style} aria-hidden="true" />;
}
