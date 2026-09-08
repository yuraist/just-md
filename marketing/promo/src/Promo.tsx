import React from "react";
import {
  AbsoluteFill,
  Img,
  OffthreadVideo,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";

// One look for the whole piece, the same as the App Store screenshots:
// flat light ground, the window with the shadow a Mac window casts, captions
// in the system font.
export const BG = "#EBEBED";
const INK = "#1D1D1F";
const MUTED = "#6E6E73";
export const FONT =
  '-apple-system, "SF Pro Display", "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif';

const fadeIn = (frame: number, start: number, length = 12) =>
  interpolate(frame, [start, start + length], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

export type Scene = {
  clip: string; // file in public/clips (.mp4, or .png for a still)
  caption: string;
  /** seconds of the source clip to skip before showing it */
  from?: number;
  /** seconds shown */
  seconds: number;
  /** source clip pixel size, to keep the window's aspect ratio */
  width: number;
  height: number;
  /** slow push-in, 1 = none */
  zoom?: number;
  /** where the push-in looks, as a fraction of the frame */
  focus?: { x: number; y: number };
  /** window rectangles inside the clip (clip pixels); the rest of the clip
   *  (the desktop between two windows) is not shown */
  windows?: { x: number; y: number; w: number; h: number; radius?: number }[];
};

const Caption: React.FC<{ text: string; delay?: number }> = ({ text, delay = 8 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame: frame - delay, fps, config: { damping: 200 } });
  const y = interpolate(enter, [0, 1], [18, 0]);
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top: 64,
        textAlign: "center",
        fontFamily: FONT,
        fontWeight: 600,
        fontSize: 54,
        letterSpacing: -0.5,
        color: INK,
        opacity: enter,
        transform: `translateY(${y}px)`,
      }}
    >
      {text}
    </div>
  );
};

/** A recorded window, corners rounded, on the flat ground under a caption. */
const WindowScene: React.FC<Scene> = ({
  clip,
  caption,
  from = 0,
  seconds,
  width,
  height,
  zoom = 1.04,
  focus = { x: 0.5, y: 0.45 },
}) => {
  const frame = useCurrentFrame();
  const { fps, width: W, height: H } = useVideoConfig();
  const total = seconds * fps;
  // The window fills the frame below the caption; a slow push-in keeps a
  // static recording alive without turning into a camera move.
  const maxW = W - 2 * 120;
  const maxH = H - 170 - 40;
  const fit = Math.min(maxW / width, maxH / height);
  const w = width * fit;
  const h = height * fit;
  const scale = interpolate(frame, [0, total], [1, zoom], {
    extrapolateRight: "clamp",
  });
  const enter = spring({ frame, fps, config: { damping: 200 } });
  return (
    <AbsoluteFill style={{ backgroundColor: BG }}>
      <Caption text={caption} />
      <div
        style={{
          position: "absolute",
          left: (W - w) / 2,
          top: 170 + (maxH - h) / 2,
          width: w,
          height: h,
          borderRadius: 22 * fit * 2,
          overflow: "hidden",
          boxShadow: "0 24px 60px rgba(0,0,0,0.22), 0 2px 8px rgba(0,0,0,0.10)",
          opacity: enter,
          transform: `translateY(${interpolate(enter, [0, 1], [24, 0])}px)`,
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            transform: `scale(${scale})`,
            transformOrigin: `${focus.x * 100}% ${focus.y * 100}%`,
          }}
        >
          <OffthreadVideo
            src={staticFile(`clips/${clip}`)}
            trimBefore={Math.round(from * fps)}
            muted
            style={{ width: "100%", height: "100%", objectFit: "cover" }}
          />
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** Two (or more) windows cut out of one recording, on the flat ground. */
const WindowsScene: React.FC<Scene> = ({ clip, caption, from = 0, seconds, width, height, windows = [], zoom = 1.03 }) => {
  const frame = useCurrentFrame();
  const { fps, width: W, height: H } = useVideoConfig();
  const total = seconds * fps;
  const maxW = W - 2 * 100;
  const maxH = H - 170 - 40;
  const fit = Math.min(maxW / width, maxH / height);
  const w = width * fit;
  const h = height * fit;
  const scale = interpolate(frame, [0, total], [1, zoom], { extrapolateRight: "clamp" });
  const enter = spring({ frame, fps, config: { damping: 200 } });
  return (
    <AbsoluteFill style={{ backgroundColor: BG }}>
      <Caption text={caption} />
      <div
        style={{
          position: "absolute",
          left: (W - w) / 2,
          top: 170 + (maxH - h) / 2,
          width: w,
          height: h,
          opacity: enter,
          transform: `translateY(${interpolate(enter, [0, 1], [24, 0])}px) scale(${scale})`,
          transformOrigin: "50% 50%",
        }}
      >
        {windows.map((r, i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              left: r.x * fit,
              top: r.y * fit,
              width: r.w * fit,
              height: r.h * fit,
              borderRadius: (r.radius ?? 22) * fit * 2,
              overflow: "hidden",
              boxShadow: "0 24px 60px rgba(0,0,0,0.22), 0 2px 8px rgba(0,0,0,0.10)",
            }}
          >
            <div style={{ position: "absolute", left: -r.x * fit, top: -r.y * fit, width: w, height: h }}>
              <OffthreadVideo
                src={staticFile(`clips/${clip}`)}
                trimBefore={Math.round(from * fps)}
                muted
                style={{ width: "100%", height: "100%" }}
              />
            </div>
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

/** A window still with a slow drift, for a scene that reads better calm. */
const StillScene: React.FC<Scene> = ({ clip, caption, seconds, width, height, zoom = 1.06, focus = { x: 0.5, y: 0.6 } }) => {
  const frame = useCurrentFrame();
  const { fps, width: W, height: H } = useVideoConfig();
  const total = seconds * fps;
  const maxW = W - 2 * 120;
  const maxH = H - 170 - 40;
  const fit = Math.min(maxW / width, maxH / height);
  const w = width * fit;
  const h = height * fit;
  const scale = interpolate(frame, [0, total], [1, zoom], { extrapolateRight: "clamp" });
  const enter = spring({ frame, fps, config: { damping: 200 } });
  return (
    <AbsoluteFill style={{ backgroundColor: BG }}>
      <Caption text={caption} />
      <div
        style={{
          position: "absolute",
          left: (W - w) / 2,
          top: 170 + (maxH - h) / 2,
          width: w,
          height: h,
          borderRadius: 22 * fit * 2,
          overflow: "hidden",
          boxShadow: "0 24px 60px rgba(0,0,0,0.22), 0 2px 8px rgba(0,0,0,0.10)",
          opacity: enter,
          transform: `translateY(${interpolate(enter, [0, 1], [24, 0])}px)`,
        }}
      >
        <Img
          src={staticFile(`clips/${clip}`)}
          style={{
            width: "100%",
            height: "100%",
            transform: `scale(${scale})`,
            transformOrigin: `${focus.x * 100}% ${focus.y * 100}%`,
          }}
        />
      </div>
    </AbsoluteFill>
  );
};

const Title: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const icon = spring({ frame, fps, config: { damping: 14, stiffness: 120 } });
  const name = spring({ frame: frame - 8, fps, config: { damping: 200 } });
  const sub = fadeIn(frame, 22, 14);
  return (
    <AbsoluteFill
      style={{
        backgroundColor: BG,
        justifyContent: "center",
        alignItems: "center",
        fontFamily: FONT,
        color: INK,
      }}
    >
      <Img
        src={staticFile("icon.png")}
        style={{
          width: 240,
          height: 240,
          transform: `scale(${interpolate(icon, [0, 1], [0.6, 1])})`,
          opacity: icon,
          filter: "drop-shadow(0 18px 30px rgba(0,0,0,0.18))",
        }}
      />
      <div
        style={{
          marginTop: 36,
          fontSize: 112,
          fontWeight: 700,
          letterSpacing: -3,
          opacity: name,
          transform: `translateY(${interpolate(name, [0, 1], [20, 0])}px)`,
        }}
      >
        JustMD
      </div>
      <div style={{ marginTop: 10, fontSize: 44, fontWeight: 500, color: MUTED, opacity: sub }}>
        Markdown, without the noise.
      </div>
    </AbsoluteFill>
  );
};

const End: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const a = spring({ frame, fps, config: { damping: 200 } });
  const b = fadeIn(frame, 16, 14);
  const c = fadeIn(frame, 30, 14);
  return (
    <AbsoluteFill
      style={{
        backgroundColor: BG,
        justifyContent: "center",
        alignItems: "center",
        fontFamily: FONT,
        color: INK,
      }}
    >
      <Img
        src={staticFile("icon.png")}
        style={{ width: 160, height: 160, opacity: a, filter: "drop-shadow(0 14px 24px rgba(0,0,0,0.16))" }}
      />
      <div style={{ marginTop: 28, fontSize: 84, fontWeight: 700, letterSpacing: -2, opacity: a }}>
        JustMD
      </div>
      <div style={{ marginTop: 14, fontSize: 46, fontWeight: 500, opacity: b }}>
        justmd.nuta.life
      </div>
      <div style={{ marginTop: 18, fontSize: 30, color: MUTED, opacity: c }}>
        A native Mac markdown editor · macOS 14 or later · Free
      </div>
    </AbsoluteFill>
  );
};

export const SCENES: Scene[] = [
  {
    clip: "typing.mp4",
    caption: "Syntax appears only on the line you edit.",
    from: 0.4,
    seconds: 7.5,
    width: 2480,
    height: 1440,
    zoom: 1.06,
    focus: { x: 0.35, y: 0.25 },
  },
  {
    clip: "readmode.mp4",
    caption: "Reading mode, one shortcut away.",
    from: 0.3,
    seconds: 5.5,
    width: 2480,
    height: 1440,
  },
  {
    clip: "images.png",
    caption: "Tables, images and links, rendered.",
    seconds: 4.5,
    width: 2480,
    height: 1440,
    zoom: 1.07,
    focus: { x: 0.5, y: 0.7 },
  },
  {
    clip: "checkboxes.mp4",
    caption: "Checkboxes you click.",
    from: 0.3,
    seconds: 4.5,
    width: 2480,
    height: 1440,
    zoom: 1.08,
    focus: { x: 0.3, y: 0.85 },
  },
  {
    clip: "themes.mp4",
    caption: "Five themes, or a palette of your own.",
    from: 1.2,
    seconds: 6,
    width: 2740,
    height: 1440,
    // recorded region {150,180} 1370×720 pt: the document at {150,180}
    // 860×720 and Settings at {1040,300} 480×475, at 2×
    windows: [
      { x: 0, y: 0, w: 1720, h: 1440 },
      { x: 1780, y: 240, w: 960, h: 950 },
    ],
  },
  {
    clip: "print.mp4",
    caption: "Print, or save as PDF.",
    from: 0.4,
    seconds: 5,
    width: 2480,
    height: 1440,
  },
];

const TITLE_SECONDS = 3.6;
const END_SECONDS = 4.5;
// Short: the windows sit in the same place from scene to scene, and a long
// crossfade shows two of them at once.
const XFADE = 0.3;

export const promoDurationInFrames = (fps: number) => {
  const scenes = SCENES.reduce((s, x) => s + x.seconds, 0);
  const cuts = SCENES.length + 1; // title→scenes…→end
  return Math.round((TITLE_SECONDS + scenes + END_SECONDS - cuts * XFADE) * fps);
};

export const Promo: React.FC = () => {
  const { fps } = useVideoConfig();
  const xfade = { timing: linearTiming({ durationInFrames: Math.round(XFADE * fps) }), presentation: fade() };
  return (
    <TransitionSeries>
      <TransitionSeries.Sequence durationInFrames={Math.round(TITLE_SECONDS * fps)}>
        <Title />
      </TransitionSeries.Sequence>
      {SCENES.map((scene) => (
        <React.Fragment key={scene.clip}>
          <TransitionSeries.Transition {...xfade} />
          <TransitionSeries.Sequence durationInFrames={Math.round(scene.seconds * fps)}>
            {scene.clip.endsWith(".png") ? (
              <StillScene {...scene} />
            ) : scene.windows ? (
              <WindowsScene {...scene} />
            ) : (
              <WindowScene {...scene} />
            )}
          </TransitionSeries.Sequence>
        </React.Fragment>
      ))}
      <TransitionSeries.Transition {...xfade} />
      <TransitionSeries.Sequence durationInFrames={Math.round(END_SECONDS * fps)}>
        <End />
      </TransitionSeries.Sequence>
    </TransitionSeries>
  );
};
