import type { ImgHTMLAttributes } from "react";
import { getLogoSrc } from "@/lib/branding";
import { cn } from "@/lib/utils";

type ZerusLogoProps = Omit<ImgHTMLAttributes<HTMLImageElement>, "src">;

export function ZerusLogo({
  alt = "",
  className,
  ...props
}: ZerusLogoProps) {
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
