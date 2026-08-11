import type { ImgHTMLAttributes } from "react";
import { getLogoSrc } from "@/lib/branding";
import { cn } from "@/lib/utils";

type GrimoireLogoProps = Omit<ImgHTMLAttributes<HTMLImageElement>, "src">;

export function GrimoireLogo({
  alt = "",
  className,
  ...props
}: GrimoireLogoProps) {
  const accessibilityProps = alt
    ? { role: "img" as const, "aria-label": alt }
    : { "aria-hidden": true as const };

  return (
    <span
      {...accessibilityProps}
      className={cn("relative inline-block", className)}
    >
      <img
        {...props}
        src={getLogoSrc("graphite")}
        alt=""
        className="brand-logo-light h-full w-full"
      />
      <img
        {...props}
        src={getLogoSrc("white")}
        alt=""
        className="brand-logo-dark h-full w-full"
      />
    </span>
  );
}
