-- The transaction screen, showing a single transaction's general journal entry.

{-# LANGUAGE OverloadedStrings, TupleSections, RecordWildCards #-} -- , FlexibleContexts

module Hledger.UI.TransactionScreen
 (transactionScreen
 ,rsSelect
 )
where

-- import Lens.Micro.Platform ((^.))
import Control.Monad.IO.Class (liftIO)
import Data.List
-- import Data.List.Split (splitOn)
-- import Data.Ord
import Data.Monoid
-- import Data.Maybe
-- import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Calendar (Day)
-- import qualified Data.Vector as V
import Graphics.Vty as Vty
-- import Safe (headDef, lastDef)
import Brick
import Brick.Widgets.List (listMoveTo)
import Brick.Widgets.Border (borderAttr)
-- import Brick.Widgets.Border.Style
-- import Brick.Widgets.Center
-- import Text.Printf

import Hledger
import Hledger.Cli hiding (progname,prognameandversion,green)
import Hledger.UI.UIOptions
-- import Hledger.UI.Theme
import Hledger.UI.UITypes
import Hledger.UI.UIUtils
import Hledger.UI.ErrorScreen

transactionScreen :: Screen
transactionScreen = TransactionScreen{
   sInit   = tsInit
  ,sDraw   = tsDraw
  ,sHandle = tsHandle
  ,tsTransaction  = (1,nulltransaction)
  ,tsTransactions = [(1,nulltransaction)]
  ,tsAccount      = ""
  }

tsInit :: Day -> Bool -> AppState -> AppState
tsInit _d _reset st@AppState{aopts=UIOpts{cliopts_=CliOpts{reportopts_=_ropts}}
                                           ,ajournal=_j
                                           ,aScreen=TransactionScreen{..}} = st
tsInit _ _ _ = error "init function called with wrong screen type, should not happen"

tsDraw :: AppState -> [Widget]
tsDraw AppState{aopts=UIOpts{cliopts_=CliOpts{reportopts_=ropts}}
                              ,aScreen=TransactionScreen{
                                   tsTransaction=(i,t)
                                  ,tsTransactions=nts
                                  ,tsAccount=acct}
                              ,aMode=mode} =
  case mode of
    Help       -> [helpDialog, maincontent]
    -- Minibuffer e -> [minibuffer e, maincontent]
    _          -> [maincontent]
  where
    -- datedesc = show (tdate t) ++ " " ++ tdescription t
    toplabel =
      str "Transaction "
      -- <+> withAttr ("border" <> "bold") (str $ "#" ++ show (tindex t))
      -- <+> str (" ("++show i++" of "++show (length nts)++" in "++acct++")")
      <+> (str $ "#" ++ show (tindex t))
      <+> str " ("
      <+> withAttr ("border" <> "bold") (str $ show i)
      <+> str (" of "++show (length nts))
      <+> togglefilters
      <+> borderQueryStr (query_ ropts)
      <+> str (" in "++T.unpack acct++")")
    togglefilters =
      case concat [
           if cleared_ ropts then ["cleared"] else []
          ,if uncleared_ ropts then ["uncleared"] else []
          ,if pending_ ropts then ["pending"] else []
          ,if real_ ropts then ["real"] else []
          ,if empty_ ropts then [] else ["nonzero"]
          ] of
        [] -> str ""
        fs -> withAttr (borderAttr <> "query") (str $ " " ++ intercalate ", " fs)
    maincontent = Widget Greedy Greedy $ do
      render $ defaultLayout toplabel bottomlabel $ str $
        showTransactionUnelidedOneLineAmounts $
        -- (if real_ ropts then filterTransactionPostings (Real True) else id) -- filter postings by --real
        t
      where
        bottomlabel = case mode of
                        -- Minibuffer ed -> minibuffer ed
                        _             -> quickhelp
        quickhelp = borderKeysStr [
           ("h", "help")
          ,("left", "back")
          ,("up/down", "prev/next")
          --,("ESC", "cancel/top")
          -- ,("a", "add")
          ,("g", "reload")
          ,("q", "quit")
          ]

tsDraw _ = error "draw function called with wrong screen type, should not happen"

tsHandle :: AppState -> Vty.Event -> EventM (Next AppState)
tsHandle st@AppState{aScreen=s@TransactionScreen{tsTransaction=(i,t)
                                                ,tsTransactions=nts
                                                ,tsAccount=acct}
                    ,aopts=UIOpts{cliopts_=copts@CliOpts{reportopts_=ropts}}
                    ,ajournal=j
                    ,aMode=mode
                    }
         ev =
  case mode of
    Help ->
      case ev of
        EvKey (KChar 'q') [] -> halt st
        _                    -> helpHandle st ev

    _ -> do
      d <- liftIO getCurrentDay
      let
        (iprev,tprev) = maybe (i,t) ((i-1),) $ lookup (i-1) nts
        (inext,tnext) = maybe (i,t) ((i+1),) $ lookup (i+1) nts
      case ev of
        EvKey (KChar 'q') [] -> halt st
        EvKey KEsc        [] -> continue $ resetScreens d st
        EvKey k [] | k `elem` [KChar 'h', KChar '?'] -> continue $ setMode Help st
        EvKey (KChar 'g') [] -> do
          d <- liftIO getCurrentDay
          (ej, _) <- liftIO $ journalReloadIfChanged copts d j
          case ej of
            Left err -> continue $ screenEnter d errorScreen{esError=err} st
            Right j' -> do
              -- got to redo the register screen's transactions report, to get the latest transactions list for this screen
              -- XXX duplicates rsInit
              let
                ropts' = ropts {depth_=Nothing
                               ,balancetype_=HistoricalBalance
                               }
                q = filterQuery (not . queryIsDepth) $ queryFromOpts d ropts'
                thisacctq = Acct $ accountNameToAccountRegex acct -- includes subs
                items = reverse $ snd $ accountTransactionsReport ropts j' q thisacctq
                ts = map first6 items
                numberedts = zip [1..] ts
                -- select the best current transaction from the new list
                -- stay at the same index if possible, or if we are now past the end, select the last, otherwise select the first
                (i',t') = case lookup i numberedts
                          of Just t'' -> (i,t'')
                             Nothing | null numberedts -> (0,nulltransaction)
                                     | i > fst (last numberedts) -> last numberedts
                                     | otherwise -> head numberedts
                st' = st{aScreen=s{tsTransaction=(i',t')
                                  ,tsTransactions=numberedts
                                  ,tsAccount=acct}}
              continue $ regenerateScreens j' d st'
        -- if allowing toggling here, we should refresh the txn list from the parent register screen
        -- EvKey (KChar 'E') [] -> continue $ regenerateScreens j d $ stToggleEmpty st
        -- EvKey (KChar 'C') [] -> continue $ regenerateScreens j d $ stToggleCleared st
        -- EvKey (KChar 'R') [] -> continue $ regenerateScreens j d $ stToggleReal st
        EvKey KUp   [] -> continue $ regenerateScreens j d st{aScreen=s{tsTransaction=(iprev,tprev)}}
        EvKey KDown [] -> continue $ regenerateScreens j d st{aScreen=s{tsTransaction=(inext,tnext)}}
        EvKey KLeft [] -> continue st''
          where
            st'@AppState{aScreen=scr} = popScreen st
            st'' = st'{aScreen=rsSelect (fromIntegral i) scr}
        _ -> continue st

tsHandle _ _ = error "event handler called with wrong screen type, should not happen"

-- | Select the nth item on the register screen.
rsSelect i scr@RegisterScreen{..} = scr{rsList=l'}
  where l' = listMoveTo (i-1) rsList
rsSelect _ scr = scr
