import type { ImgHTMLAttributes } from "react";
import { getLogoSrc, type LogoStyle } from "@/lib/branding";
import { cn } from "@/lib/utils";

type ZerusLogoProps = Omit<ImgHTMLAttributes<HTMLImageElement>, "src"> & {
  tone?: LogoStyle | "auto";
};

export function ZerusLogo({
  alt = "",
  className,
  tone = "auto",
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
      {tone === "auto" ? (
        <>
          <img
            {...props}
            src={getLogoSrc("graphite")}
            alt=""
            className="zerus-logo-light h-full w-full"
          />
          <img
            {...props}
            src={getLogoSrc("white")}
            alt=""
            className="zerus-logo-dark h-full w-full"
          />
        </>
      ) : (
        <img {...props} src={getLogoSrc(tone)} alt="" className="h-full w-full" />
      )}
    </span>
  );
}
