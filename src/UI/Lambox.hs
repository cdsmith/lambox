{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}

-- TODO Reorganize everything

module UI.Lambox
  ( module UI.Lambox
  , Config(..)
  --, Box(..)
  , BoxAttributes(..)
  , Borders(..)
  , AlignV(..)
  , AlignH(..)
  , Title(..)
  , Direction(..)
  , Axis(..)
  , Event(..) -- from ncurses
  , Curses -- from ncurses
  , CursorMode(..) --maybe don't re-export ncurses stuff?
  , setCursorMode
  ) where --remember to export relevant ncurses stuff as well (like events, curses, glyphs, etc) (???)

import Data.List (sort)

import UI.NCurses
import UI.NCurses.Panel

import UI.Lambox.Internal.Types
import UI.Lambox.Internal.Util

--TODO:
-- Boxes/Panels
-- |- borders (dash '-' '|' or hash '#' or dot '*' ******** or plus '+' (or other char)
-- |- gaps
-- |- dimension
-- |- ordering
-- |- position
-- Widgets
-- |- scroll
-- |- text input
-- |- check/radial boxes
-- |- tabs
-- Updaters

-- | Wait for condition to be met before continuing
waitFor :: Window -> (Event -> Bool) -> Curses ()
waitFor w p = onEvent w p (const $ return ())

-- | Similar to onEvent, but does not \'consume\' event
onEvent' :: Maybe Event -> (Event -> Bool) -> (Event -> Curses a) -> Curses ()
onEvent' (Just event) p action = if p event then action event >> pure () else pure ()
onEvent' Nothing _ _           = pure ()

-- | Perform action if event passed meets the event condition, else do nothing
onEvent :: Window {- replace with Box -} -> (Event -> Bool) -> (Event -> Curses a) -> Curses ()
onEvent window p action = getEvent window Nothing >>= \event -> onEvent' event p action

-- | Similar to onEvent but happens on any event within the default window
onEventGlobal :: (Event -> Bool) -> (Event -> Curses a) -> Curses ()
onEventGlobal p action = do
  def <- defaultWindow
  getEvent def Nothing >>= \event -> onEvent' event p action

-- | Create a panel given a Box type. Because the tui panel uses NCurses'
-- Panel and Window type, it cannot be garbage collected and must be
-- deleted manually with `deletePanel`
newBox :: Config -> Curses Box
newBox conf@Config{..} = do
  win <- newWindow configHeight configWidth configY configX
  pan <- newPanel win
  let box = Box conf win pan
  updateWindow win $ updateBox box
  refreshPanels
  return box

-- setBox :: Box -> Curses a -> Curses ()
-- configBox :: Box -> Config -> Curses Box

-- | Delete panel
deleteBox :: Box -> Curses ()
deleteBox (Box _ win pan) = deletePanel pan >> closeWindow win

{-
deleteBoxes :: [Box] -> Curses ()
deleteBoxes = foldMap deleteBox -}

-- | Literally just a synonym for render
update :: Curses ()
update = refreshPanels >> render

-- | Start the program
lambox :: Curses a -> IO a
lambox f = runCurses (setEcho False >> setCursorMode CursorInvisible >> f)

-- TODO :: default configs like full(screen), up half, down third, etc, using direction and ratio
-- config :: Direction -> Ratio -> Config

-- | Take a box and a pair of local coordinates and print a string within it
writeStr :: Box -> Integer -> Integer -> String -> Curses ()
writeStr (Box conf win pan) x y str = updateWindow win $ do
  moveCursor y x
  drawString str

-- | Like writeStr but with any showable type
writeShow :: Show a => Box -> Integer -> Integer -> a -> Curses ()
writeShow box x y = ((writeStr box x y) . show)

-- | Take a box and split it into two boxes, returning the new
-- box and altering the passed box as a side effect (CAUTION!)
-- The direction determines where the new box is in relation
-- to the passed box, and the fraction is the ratio of the
-- length or width of the new box to the old.
splitFromBox :: RealFrac a => Box -> Direction -> a -> BoxAttributes -> Curses (Box, Box) -- return Curses (Box, Box) (oldbox, newbox) with updated config settings
splitFromBox (Box Config{..} win pan) dir ratio attrs = do
  case dir of
    _ -> do -- DirUp
      let nHeight2 = ratioIF configHeight ratio
          nHeight1 = configHeight - nHeight2
          nuY2 = configY
          nuY1 = configY + nHeight2
      updateWindow win $ do
        resizeWindow nHeight1 configWidth -- have to redraw borders and title, to fix that bottom border bug
        moveWindow nuY1 configX
      let nConfig = Config configX nuY2 configWidth nHeight2 attrs
      box2 <- newBox nConfig
      let nbox1 = Box (Config configX nuY1 configWidth nHeight1 configAttrs) win pan
      pure (nbox1,box2)

-- | Take a config for an area then given the axis and a decimal,
-- split the area into two boxes. The decimal is that ratio between
-- the respective dimensions of the first box and second box.
splitBox :: RealFrac a => Config -> Axis -> a -> Curses (Box,Box)
splitBox Config{..} axis ratio = splitBox' configX configY configWidth configHeight configAttrs configAttrs axis ratio


-- | Take x and y coordinates, dimensions, axis, ratio, and
-- two attribute lists to split the area into two boxes, configuring
-- each box to the respective attributes (top/left takes first one)
splitBox' :: RealFrac a => Integer -> Integer -> Integer -> Integer -> BoxAttributes -> BoxAttributes -> Axis -> a -> Curses (Box,Box)
splitBox' x y width height attrs1 attrs2 axis ratio = do
  (conf1, conf2) <- case axis of
    Horizontal -> do
      let width1 = ratioIF width ratio
          width2 = width - width1
          x1 = x
          x2 = x + width1
      pure
        ( Config x1 y width1 height attrs1
        , Config x2 y width2 height attrs2
        )
    Vertical -> do
      let height1 = ratioIF height ratio
          height2 = height - height1
          y1 = y
          y2 = y + height1
      pure
        ( Config x y1 width height1 attrs1
        , Config x y2 width height2 attrs2
        )
  box1 <- newBox conf1
  box2 <- newBox conf2
  pure (box1,box2)

setBoxAttributes :: Box -> BoxAttributes -> Curses Box
setBoxAttributes (Box config win pan) newAttrs = do
  let newBox = Box (config { configAttrs = newAttrs }) win pan
  updateWindow win $ updateBox newBox
  return newBox

setBorders :: Box -> Borders -> Curses Box
setBorders box@(Box cfg _ _) newBorders = do
  setBoxAttributes box (configAttrs cfg) { attrBorders = newBorders }

setTitle :: Box -> Maybe Title -> Curses Box
setTitle box@(Box cfg _ _) newTitle = do
  setBoxAttributes box (configAttrs cfg) { attrTitle = newTitle }

updateBox :: Box -> Update ()
updateBox (Box Config{..} _ _) = do
  case attrBorders configAttrs of
    None -> drawBox Nothing Nothing
    Line -> drawBox (Just glyphLineV) (Just glyphLineH)
    Hash -> drawBorder
      (Just glyphStipple)
      (Just glyphStipple)
      (Just glyphStipple)
      (Just glyphStipple)
      (Just glyphStipple)
      (Just glyphStipple)
      (Just glyphStipple)
      (Just glyphStipple)
    _ -> drawBox (Just glyphLineV) (Just glyphLineH) -- TODO: Complete
  case attrTitle configAttrs of
    Nothing -> return ()
    Just (Title title vAlign hAlign) -> do
      let vert = case vAlign of
            AlignLeft -> 1
            AlignCenter -> (configWidth `quot` 2) - ((toInteger $ length title) `quot` 2)
            AlignRight -> (configWidth-1) - (toInteger $ length title)
          horz = case hAlign of
            AlignTop -> 0
            AlignBot -> configHeight-1
      moveCursor horz vert >> drawString title
