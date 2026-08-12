import { useEffect, useState } from "react";
import type { Icon } from "@tabler/icons-react";
import { Folder, FolderOpen } from "lucide-react";
import { isEmojiValue, tablerIconName } from "@/lib/type-icons";

const loadedIcons = new Map<string, Icon>();
let catalogPromise: ReturnType<typeof importTablerCatalog> | null = null;

function importTablerCatalog() {
  return import("@/lib/tabler-icon-catalog");
}

function loadTablerIcon(name: string): Promise<Icon | null> {
  const loaded = loadedIcons.get(name);
  if (loaded) return Promise.resolve(loaded);
  catalogPromise ??= importTablerCatalog();
  return catalogPromise.then(({ TABLER_ICONS_BY_NAME }) => {
    const Icon = TABLER_ICONS_BY_NAME.get(name) ?? null;
    if (Icon) loadedIcons.set(name, Icon);
    return Icon;
  });
}

/**
 * The icon for a type: its custom Tabler icon (or a legacy emoji), otherwise
 * the default folder glyph. The offline Tabler catalog loads on demand.
 */
export function TypeIcon({
  icon,
  open = false,
  size,
  className,
  style,
}: {
  /** Namespaced Tabler icon or legacy emoji stored for this type, if any. */
  icon?: string;
  /** Renders the fallback as an open folder (expanded tree rows). */
  open?: boolean;
  size: number;
  className?: string;
  style?: React.CSSProperties;
}) {
  const tablerName = tablerIconName(icon);
  const [loaded, setLoaded] = useState<{ name: string; Icon: Icon } | null>(() => {
    const Icon = tablerName ? loadedIcons.get(tablerName) : null;
    return tablerName && Icon ? { name: tablerName, Icon } : null;
  });

  useEffect(() => {
    let current = true;
    if (!tablerName) {
      setLoaded(null);
      return () => {
        current = false;
      };
    }
    void loadTablerIcon(tablerName).then((loaded) => {
      if (current) {
        setLoaded(loaded ? { name: tablerName, Icon: loaded } : null);
      }
    });
    return () => {
      current = false;
    };
  }, [tablerName]);

  if (isEmojiValue(icon)) {
    return (
      <span
        aria-hidden="true"
        className={className}
        style={{
          fontSize: size,
          lineHeight: 1,
          width: size,
          display: "inline-flex",
          justifyContent: "center",
          ...style,
        }}
      >
        {icon}
      </span>
    );
  }
  if (loaded?.name === tablerName) {
    const CustomIcon = loaded.Icon;
    return (
      <CustomIcon
        size={size}
        stroke={1.8}
        className={className}
        style={style}
        aria-hidden="true"
      />
    );
  }
  const Fallback = open ? FolderOpen : Folder;
  return <Fallback size={size} className={className} style={style} />;
}
