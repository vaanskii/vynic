export const revealTransition = {
  duration: 0.58,
  ease: [0.16, 1, 0.3, 1] as const,
};

export const revealFromBottom = {
  hidden: { opacity: 0, y: 28 },
  show: { opacity: 1, y: 0 },
};

export const staggerParent = {
  hidden: {},
  show: {
    transition: {
      staggerChildren: 0.06,
    },
  },
};
