import { gsap } from "gsap";
import { type RefObject, useEffect } from "react";
import { motionQuery, pointer } from "../../lib/motion";

type PointerDepthTargets = {
  /** Element that receives pointer events (listeners live only here). */
  area: RefObject<HTMLElement | null>;
  /** Tilts and shifts toward the pointer. */
  depth?: RefObject<HTMLElement | null>;
  /** Moves slightly against the pointer for layered parallax. */
  counter?: RefObject<HTMLElement | null>;
  /** Soft light that follows the pointer inside `area`. */
  light?: RefObject<HTMLElement | null>;
};

/**
 * Subtle pointer-reactive depth for desktop fine pointers. No React state:
 * pointer positions go straight into GSAP quickTo setters, which only run
 * while the pointer is over `area` and settle back to rest when it leaves.
 * Touch, small screens and reduced motion get nothing.
 */
export function usePointerDepth({ area, depth, counter, light }: PointerDepthTargets) {
  useEffect(() => {
    const areaEl = area.current;
    if (!areaEl) return;
    const media = gsap.matchMedia();

    media.add(motionQuery.finePointer, () => {
      const depthEl = depth?.current;
      const counterEl = counter?.current;
      const lightEl = light?.current;
      const tween = { duration: pointer.lag, ease: "power3.out" };
      const setters = {
        rotateY: depthEl ? gsap.quickTo(depthEl, "rotationY", tween) : null,
        rotateX: depthEl ? gsap.quickTo(depthEl, "rotationX", tween) : null,
        x: depthEl ? gsap.quickTo(depthEl, "x", tween) : null,
        y: depthEl ? gsap.quickTo(depthEl, "y", tween) : null,
        counterX: counterEl ? gsap.quickTo(counterEl, "x", tween) : null,
        counterY: counterEl ? gsap.quickTo(counterEl, "y", tween) : null,
        lightX: lightEl ? gsap.quickTo(lightEl, "x", { duration: 1.1, ease: "power3.out" }) : null,
        lightY: lightEl ? gsap.quickTo(lightEl, "y", { duration: 1.1, ease: "power3.out" }) : null,
        lightOpacity: lightEl ? gsap.quickTo(lightEl, "autoAlpha", { duration: 0.6, ease: "power2.out" }) : null,
      };
      if (depthEl) gsap.set(depthEl, { transformPerspective: 1400 });

      // One read + write per frame at most, and only while the pointer is here.
      let frame = 0;
      let clientX = 0;
      let clientY = 0;
      const apply = () => {
        frame = 0;
        const bounds = areaEl.getBoundingClientRect();
        // -1…1 from the centre of the area.
        const nx = ((clientX - bounds.left) / bounds.width) * 2 - 1;
        const ny = ((clientY - bounds.top) / bounds.height) * 2 - 1;
        setters.rotateY?.(nx * pointer.tilt);
        setters.rotateX?.(-ny * pointer.tilt * 0.6);
        setters.x?.(nx * pointer.shift);
        setters.y?.(ny * pointer.shift * 0.6);
        setters.counterX?.(-nx * pointer.shift * 0.8);
        setters.counterY?.(-ny * pointer.shift * 0.5);
        setters.lightX?.(clientX - bounds.left);
        setters.lightY?.(clientY - bounds.top);
        setters.lightOpacity?.(1);
      };
      const move = (event: PointerEvent) => {
        if (event.pointerType !== "mouse") return;
        clientX = event.clientX;
        clientY = event.clientY;
        if (!frame) frame = requestAnimationFrame(apply);
      };
      const leave = () => {
        if (frame) cancelAnimationFrame(frame);
        frame = 0;
        setters.rotateY?.(0);
        setters.rotateX?.(0);
        setters.x?.(0);
        setters.y?.(0);
        setters.counterX?.(0);
        setters.counterY?.(0);
        setters.lightOpacity?.(0);
      };

      areaEl.addEventListener("pointermove", move);
      areaEl.addEventListener("pointerleave", leave);

      return () => {
        areaEl.removeEventListener("pointermove", move);
        areaEl.removeEventListener("pointerleave", leave);
        if (frame) cancelAnimationFrame(frame);
        gsap.killTweensOf([depthEl, counterEl, lightEl].filter(Boolean));
        gsap.set([depthEl, counterEl].filter(Boolean), { clearProps: "transform" });
      };
    });

    return () => media.revert();
  }, [area, depth, counter, light]);
}
