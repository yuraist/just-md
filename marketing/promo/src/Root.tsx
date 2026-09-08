import "./index.css";
import { Composition } from "remotion";
import { Promo, promoDurationInFrames } from "./Promo";

const FPS = 30;

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="JustMDPromo"
      component={Promo}
      durationInFrames={promoDurationInFrames(FPS)}
      fps={FPS}
      width={1920}
      height={1080}
    />
  );
};
