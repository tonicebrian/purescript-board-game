module App.Board where

import Prelude
import Camera (Camera, Vec2, defaultCamera, screenPan, toViewBox, zoomOn)
import Data.Array as Array
import Data.FunctorWithIndex (mapWithIndex)
import Data.GameMap (BackgroundMap(..), CellData(..), GameMap(..), generateMap, maximumMapSize, neighbours)
import Data.Int (odd, toNumber)
import Data.Lens (over)
import Data.Lens.Index (ix)
import Data.Lens.Iso.Newtype (_Newtype)
import Data.Lens.Record (prop)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.MediaType (MediaType(..))
import Data.MouseButton (MouseButton(..), isPressed)
import Data.Set (Set)
import Data.Set as Set
import Data.String (joinWith)
import Data.Symbol (SProxy(..))
import Data.Tuple (Tuple(..), uncurry)
import Data.Typelevel.Num (D6, d0, d1, d5)
import Data.Vec (Vec, vec2, (!!))
import Data.Vec as Vec
import Effect.Class (class MonadEffect)
import Halogen (AttrName(..), get, gets, modify_)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Svg.Attributes as SA
import Halogen.Svg.Elements as SE
import Halogen.Svg.Indexed as SI
import Math (cos, pi, sin, sqrt)
import Web.UIEvent.MouseEvent as MouseEvent
import Web.UIEvent.WheelEvent (WheelEvent)
import Web.UIEvent.WheelEvent as WheelEent

type SelectionState
  = { position :: Tuple Int Int
    , neighbours :: Set (Tuple Int Int)
    }

type State
  = { backgroundMap :: BackgroundMap
    , lastMousePosition :: Vec2 Number
    , camera :: Camera
    , windowSize :: Vec2 Number
    , gameMap :: GameMap
    , cellSize :: Number
    , mapPadding :: Vec2 Number
    , selectedCell :: Maybe SelectionState
    }

data Action
  = Initialize
  | HandleMouseDown
  | HandleMouseUp
  | HandleMouseMove MouseEvent.MouseEvent
  | HandleScroll WheelEvent
  | ChangeCellData (Tuple Int Int)
  | SelectCell (Tuple Int Int)

type Input
  = { backgroundMap :: BackgroundMap
    , cellSize :: Number
    , mapPadding :: Vec2 Number
    }

_rawHtml :: SProxy "rawHtml"
_rawHtml = SProxy

_gameMap :: SProxy "gameMap"
_gameMap = SProxy

component :: forall q o m. MonadEffect m => H.Component HH.HTML q Input o m
component =
  H.mkComponent
    { initialState:
      \{ mapPadding, backgroundMap: backgroundMap@(BackgroundMap { width, height }), cellSize } ->
        { backgroundMap
        , camera: defaultCamera (Tuple 0.3 4.0)
        , lastMousePosition: zero
        , mapPadding
        , cellSize
        , windowSize: vec2 1500.0 1500.0
        , gameMap: generateMap $ (maximumMapSize cellSize $ mapPadding + (toNumber <$> vec2 width height))
        , selectedCell: Nothing
        }
    , render
    , eval:
      H.mkEval
        $ H.defaultEval
            { handleAction = handleAction
            , initialize = Just Initialize
            }
    }

render :: forall m cs. MonadEffect m => State -> H.ComponentHTML Action cs m
render state =
  SE.svg
    [ SA.height $ state.windowSize !! d0
    , SA.width $ state.windowSize !! d1
    , HP.id_ "board"
    , toViewBox state.windowSize state.camera
    , HE.onWheel $ HandleScroll >>> Just
    , HE.onMouseMove $ HandleMouseMove >>> Just
    ]
    [ renderBackgroundMap state.mapPadding state.backgroundMap
    , renderGameMap state.cellSize state.selectedCell state.gameMap
    ]

renderGameMap :: forall m cs. Number -> Maybe SelectionState -> GameMap -> H.ComponentHTML Action cs m
renderGameMap cellSize selectionState (GameMap gameMap) =
  SE.g [] $ join
    $ flip Array.mapWithIndex gameMap \x inner ->
        join
          $ flip Array.mapWithIndex inner \y cellData -> renderCell cellData x y
  where
  renderCell cellData x y = Array.cons hexagon content
    where
    hexagon =
      renderFlatHexagon cellSize (vec2 screenX screenY)
        [ SA.class_ classes
        , HE.onClick
            $ \event ->
                Just
                  if MouseEvent.ctrlKey event then
                    ChangeCellData (Tuple x y)
                  else
                    SelectCell (Tuple x y)
        , HE.onMouseMove $ HandleMouseMove >>> Just
        ]

    content = case cellData of
      EmptyCell -> []
      GamePiece ->
        [ SE.rect
            [ SA.x (screenX - pieceWidth / 2.0)
            , SA.y (screenY - pieceHeight / 2.0)
            , SA.height pieceHeight
            , SA.width pieceWidth
            , SA.class_ "board__piece"
            ]
        ]
        where
        pieceHeight = cellSize * 1.2

        pieceWidth = cellSize

    classes =
      joinWith " " $ append [ "board__hexagon" ] $ fromMaybe [] $ selectionState
        <#> \selection ->
            if selection.position == Tuple x y then
              [ "board__hexagon--selected" ]
            else
              if Set.member (Tuple x y) selection.neighbours then
                [ "board__hexagon--selection-neighbour" ]
              else
                []

    verticalSize = cellSize * sqrt 3.0

    screenX = cellSize * (1.5 * toNumber x + 1.0)

    screenY = verticalSize * (toNumber y + if odd x then 1.0 else 0.5)

renderBackgroundMap :: forall m cs. Vec2 Number -> BackgroundMap -> H.ComponentHTML Action cs m
renderBackgroundMap mapPadding (BackgroundMap { width, height, url }) =
  SE.foreignObject
    [ SA.width $ toNumber width
    , SA.height $ toNumber height
    , SA.x $ (mapPadding !! d0) / 2.0
    , SA.y $ (mapPadding !! d1) / 2.0
    ]
    [ HH.object
        [ HP.type_ (MediaType "image/svg+xml")
        , HP.attr (AttrName "data") ("assets/" <> url)
        , HP.width width
        , HP.height height
        ]
        []
    ]

hexagonCorner :: Number -> Int -> Vec2 Number -> Vec2 Number
hexagonCorner size nth center =
  center
    + vec2
        (size * cos angle)
        (size * sin angle)
  where
  angle = toNumber nth * pi / 3.0

renderFlatHexagon ::
  forall cs m.
  Number ->
  Vec2 Number ->
  Array
    ( HP.IProp
        SI.SVGpath
        Action
    ) ->
  H.ComponentHTML Action cs m
renderFlatHexagon size center props =
  SE.path
    $ Array.snoc props
    $ SA.d
    $ SA.Abs
    <$> Array.snoc commands SA.Z
  where
  commands =
    Vec.toArray
      $ flip mapWithIndex vec \index point ->
          (if index == 0 then SA.M else SA.L) (point !! d0)
            (point !! d1)

  vec :: Vec D6 (Vec2 Number)
  vec = Vec.range d0 d5 <#> \nth -> hexagonCorner size nth center

handleAction :: forall cs o m. MonadEffect m => Action → H.HalogenM State Action cs o m Unit
handleAction = case _ of
  Initialize -> do
    pure unit
  HandleMouseDown -> pure unit
  HandleMouseUp -> pure unit
  HandleMouseMove event -> do
    { lastMousePosition, windowSize, backgroundMap: BackgroundMap background } <- get
    let
      mouseButtonState = MouseEvent.buttons event

      mousePosition = toNumber <$> vec2 (MouseEvent.clientX event) (MouseEvent.clientY event)

      updateCamera camera
        | isPressed LeftMouseButton mouseButtonState = screenPan (mousePosition - lastMousePosition) camera
        | otherwise = camera
    modify_ \state ->
      state
        { lastMousePosition = mousePosition
        , camera = updateCamera state.camera
        }
  HandleScroll event -> do
    mousePosition <- gets _.lastMousePosition
    let
      delta = WheelEent.deltaY event
    when (delta /= 0.0) do
      modify_ \state ->
        state
          { camera =
            zoomOn mousePosition
              ( if delta < 0.0 then 1.1 else 1.0 / 1.1
              )
              state.camera
          }
  ChangeCellData (Tuple x y) -> do
    modify_
      $ over (prop _gameMap <<< _Newtype <<< ix x <<< ix y) case _ of
          EmptyCell -> GamePiece
          GamePiece -> EmptyCell
  SelectCell position -> do
    modify_ \state ->
      state
        { selectedCell =
          if (state.selectedCell <#> _.position) == Just position then
            Nothing
          else
            Just
              { position
              , neighbours:
                Set.fromFoldable $ map (\v -> Tuple (v !! d0) (v !! d1))
                  $ neighbours
                  $ uncurry vec2 position
              }
        }
