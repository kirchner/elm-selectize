module ArchitectureTests exposing (..)

import ArchitectureTest exposing (..)
import ArchitectureTest.Types exposing (..)
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer)
import Random
import Selectize.Selectize as S
import Test exposing (..)


suite : Test
suite =
    describe "architecture tests"
        [ testUpdate ]



{- actual tests -}


testUpdate : Test
testUpdate =
    concat
        [ msgTestWithPrecondition "reset model if textfield blured and preventBlur is False"
            app
            textfieldBlured
            (\model -> not model.menu.preventBlur)
          <|
            \_ _ _ _ finalModel ->
                finalModel.menu
                    |> expectReset
        , msgTestWithPrecondition "do not change model if textfield blured and preventBlur is True"
            app
            textfieldBlured
            (\model -> model.menu.preventBlur)
          <|
            \_ _ beforeMsgModel _ finalModel ->
                beforeMsgModel
                    |> Expect.equal finalModel
        , msgTest "model is reseted after sth is selected"
            app
            (Fuzz.oneOf
                [ select
                , selectKeyboardFocusAndBlur
                ]
            )
          <|
            \_ _ _ _ finalModel ->
                finalModel.menu
                    |> expectReset
        , invariantTest "mouseFocus and keyboardFocus are always from the list"
            app
          <|
            \_ _ finalModel ->
                finalModel.menu
                    |> Expect.all
                        [ .mouseFocus >> expectMember
                        , .zipList >> Maybe.map S.currentEntry >> expectMember
                        ]
        , msgTest "First possible entry is keyboardFocused after query change"
            app
            setQuery
          <|
            \_ _ _ _ finalModel ->
                if finalModel.menu.open then
                    finalModel.menu.zipList
                        |> Maybe.map S.currentEntry
                        |> Maybe.map entry
                        |> Expect.equal
                            (treesWithoutDivider
                                |> S.filter finalModel.menu.query
                                |> List.head
                            )
                else
                    Expect.pass
        , msgTest "model is unchanged after clear selection"
            app
            clearSelection
          <|
            \_ _ beforeMsgModel _ finalModel ->
                beforeMsgModel
                    |> Expect.equal finalModel
        ]



{- expectations -}


expectReset : S.State String -> Expectation
expectReset menu =
    menu
        |> Expect.all
            [ .query >> Expect.equal ""
            , .zipList >> Expect.equal Nothing
            , .filteredEntries >> Expect.equal Nothing
            , .mouseFocus >> Expect.equal Nothing
            , .open >> Expect.false "Expected the menu to be closed"
            ]


expectMember : Maybe String -> Expectation
expectMember maybeFocus =
    case maybeFocus of
        Just focus ->
            List.member (S.entry focus) trees
                |> Expect.true "Expected the focus to be in the list of possible entries"

        Nothing ->
            Expect.pass



{- setup -}


app : TestedApp Model (S.Msg String)
app =
    { model = ConstantModel init
    , update = BeginnerUpdate update
    , msgFuzzer = msg
    }


type alias Model =
    { menu : S.State String
    , selection : Maybe String
    }


init : Model
init =
    { menu = S.closed "menu" identity trees
    , selection = Nothing
    }


update : S.Msg String -> Model -> Model
update msg model =
    let
        ( newMenu, _, _ ) =
            S.update (\_ -> ()) model.selection model.menu msg
    in
    { model | menu = newMenu }



{- msg fuzzer -}


msg : Fuzzer (S.Msg String)
msg =
    Fuzz.oneOf
        -- TODO: add setPreventBlur
        [ noOp
        , textfieldFocused
        , textfieldBlured
        , blurTextfield
        , setQuery
        , setMouseFocus
        , select
        , setKeyboardFocus
        , selectKeyboardFocusAndBlur
        , clearSelection
        ]


noOp : Fuzzer (S.Msg String)
noOp =
    Fuzz.constant S.NoOp


textfieldFocused : Fuzzer (S.Msg String)
textfieldFocused =
    Fuzz.map2 S.OpenMenu
        (Fuzz.map2
            S.Heights
            (listCount (Fuzz.intRange 0 42 |> Fuzz.map toFloat) (List.length trees))
            (Fuzz.intRange 0 100 |> Fuzz.map toFloat)
        )
        (Fuzz.intRange 0 1000 |> Fuzz.map toFloat)


textfieldBlured : Fuzzer (S.Msg String)
textfieldBlured =
    Fuzz.constant S.CloseMenu


blurTextfield : Fuzzer (S.Msg String)
blurTextfield =
    Fuzz.constant S.BlurTextfield


setQuery : Fuzzer (S.Msg String)
setQuery =
    Fuzz.string |> Fuzz.map S.SetQuery


setMouseFocus : Fuzzer (S.Msg String)
setMouseFocus =
    (treesPart1 ++ treesPart2)
        |> List.map Fuzz.constant
        |> Fuzz.oneOf
        |> Fuzz.maybe
        |> Fuzz.map S.SetMouseFocus


select : Fuzzer (S.Msg String)
select =
    (treesPart1 ++ treesPart2)
        |> List.map Fuzz.constant
        |> Fuzz.oneOf
        |> Fuzz.map S.Select


setKeyboardFocus : Fuzzer (S.Msg String)
setKeyboardFocus =
    Fuzz.map2 S.SetKeyboardFocus
        movement
        (Fuzz.intRange 0 1000 |> Fuzz.map toFloat)


selectKeyboardFocusAndBlur : Fuzzer (S.Msg String)
selectKeyboardFocusAndBlur =
    Fuzz.constant S.SelectKeyboardFocusAndBlur


movement : Fuzzer S.Movement
movement =
    Fuzz.oneOf
        [ Fuzz.constant S.Up
        , Fuzz.constant S.Down
        ]


clearSelection : Fuzzer (S.Msg String)
clearSelection =
    Fuzz.constant S.ClearSelection



{- fuzzer -}


listCount : Fuzzer a -> Int -> Fuzzer (List a)
listCount fuzzer count =
    if count > 1 then
        Fuzz.map2 (\a rest -> a :: rest)
            fuzzer
            (listCount fuzzer (count - 1))
    else
        fuzzer |> Fuzz.map (\a -> [ a ])



{- data -}


entry tree =
    S.LEntry tree tree


trees : List (S.Entry String)
trees =
    List.concat
        [ [ S.divider "First Part" ]
        , treesPart1 |> List.map S.entry
        , [ S.divider "Second Part" ]
        , treesPart2 |> List.map S.entry
        ]


treesWithoutDivider : List (S.LEntry String)
treesWithoutDivider =
    List.concat
        [ treesPart1 |> List.map entry
        , treesPart2 |> List.map entry
        ]


treesPart1 : List String
treesPart1 =
    [ "Abelia x grandiflora"
    , "Abienus festuschristus"
    , "Abies alba"
    , "Abies balsamea"
    , "Abies cephalonica"
    , "Abies concolor"
    , "Abies equi-trojani"
    , "Abies grandis"
    , "Abies holophylla"
    , "Abies homolepis"
    , "Abies koreana"
    , "Abies lasiocarpa"
    , "Abies nordmanniana"
    , "Abies pinsapo"
    , "Abies procera"
    , "Abies procera 'Glauca'"
    , "Abies veitchii"
    , "Acacia dealbata"
    , "Acacia karroo"
    , "Acacia retinodes"
    , "Acer buergerianum"
    , "Acer campestre"
    , "Acer cappadocicum"
    , "Acer carpinifolium"
    , "Acer caudatum subsp. caudatum"
    , "Acer circinatum"
    , "Acer cissifolium"
    , "Acer coriaceifolium"
    , "Acer davidii"
    , "Acer davidii subsp. grosserii"
    , "Acer griseum"
    , "Acer japonicum 'Aconitifolium'"
    , "Acer macrophyllum"
    , "Acer mandshuricum"
    , "Acer monspessulanum"
    , "Acer negundo"
    , "Acer opalus"
    , "Acer opalus ssp. obtusatum"
    , "Acer palmatum"
    , "Acer palmatum 'Dissectum Viridis'"
    , "Acer pensylvanicum"
    , "Acer platanoides"
    , "Acer platanoides 'Crimson King'"
    , "Acer platanoides f. drummondii"
    , "Acer pseudoplatanus"
    , "Acer pseudoplatanus 'Leopoldii'"
    , "Acer pseudoplatanus f. atropurpureum"
    , "Acer rubrum"
    , "Acer rufinerve"
    , "Acer saccharinum"
    , "Acer saccharum"
    , "Acer sempervirens"
    , "Acer tataricum"
    , "Acer tataricum subsp. ginnala"
    , "Acer tegmentosum"
    , "Acer triflorum"
    , "Acer x zoeschense"
    , "Actinidia deliciosa"
    , "Actinidia kolomikta"
    , "Adonidia merrillii"
    , "Aesculus flava"
    , "Aesculus glabra"
    , "Aesculus hippocastanum"
    , "Aesculus indica"
    , "Aesculus parviflora"
    , "Aesculus pavia"
    , "Aesculus turbinata"
    , "Aesculus x carnea"
    , "Aesculus x mutabilis 'Penduliflora'"
    , "Aesculus x neglecta 'Erythroblastos'"
    , "Afzelia africana"
    , "Ailanthus altissima"
    , "Akebia quinata"
    , "Alangium platanifolium"
    , "Albizia julibrissin"
    , "Allocasuarina luehmannii"
    , "Alnus cordata"
    , "Alnus glutinosa"
    , "Alnus incana"
    , "Alnus sinuata"
    , "Alnus viridis"
    , "Amelanchier asiatica"
    , "Amelanchier laevis"
    , "Amelanchier lamarckii"
    , "Amelanchier ovalis"
    , "Amelanchier spicata"
    , "Amorpha fructicosa"
    , "Anacardium occidentale"
    , "Anagyris foetida"
    , "Andromeda polifolia"
    , "Annona cherimola"
    , "Aralia elata"
    , "Araucaria araucana"
    , "Araucaria bidwillii"
    , "Araucaria columnaris"
    , "Araucaria cunninghamii"
    , "Araucaria heterophylla"
    , "Arbutus menziesii"
    , "Arbutus unedo"
    , "Argania spinosa"
    , "Argyrocytisus battandieri"
    , "Aronia arbutifolia"
    , "Aronia melanocarpa"
    , "Aronia x prunifolia"
    , "Asimina triloba"
    , "Asparagus acutifolius"
    , "Aucuba japonica"
    , "Averrhoa carambola"
    , "Barringtonia asiatica"
    , "Bauhinia kockiana"
    , "Bauhinia x blakeana"
    , "Berberis julianae"
    , "Berberis koreana"
    , "Berberis thunbergii"
    , "Berberis vulgaris"
    , "Betula alleghaniensis"
    , "Betula alnoides subsp. alnoides"
    , "Betula alnoides subsp. luminifera"
    , "Betula costata"
    , "Betula dahurica"
    , "Betula ermanii"
    , "Betula insignis"
    , "Betula lenta"
    , "Betula lenta f. uber"
    , "Betula maximowicziana"
    , "Betula nigra"
    , "Betula papyrifera"
    , "Betula pendula"
    , "Betula pendula f. dalecarlica"
    , "Betula populifolia"
    , "Betula pubescens"
    , "Betula utilis var. jacquemontii 'Doorenbos'"
    , "Bougainvillea glabra"
    , "Bougainvillea spectabilis"
    , "Brachychiton acerifolius"
    , "Brachychiton discolor"
    , "Brachychiton populneus"
    , "Brachychiton rupestris"
    , "Broussonetia papyrifera"
    , "Buddleja alternifolia"
    , "Buddleja davidii"
    , "Buddleja globosa"
    , "Buddleja x weyeriana"
    , "Butyrospermum parkii"
    , "Buxus sempervirens"
    , "Caesalpinia gilliesii"
    , "Calicotome spinosa"
    , "Callicarpa dichotoma"
    , "Callistemon citrinus"
    , "Calocedrus decurrens"
    , "Calocedrus decurrens 'Aureovariegata'"
    , "Calycanthus fertilis"
    , "Calycanthus floridus"
    , "Camellia japonica"
    , "Campsis radicans"
    , "Campsis x tagliabuana"
    , "Capparis spinosa"
    , "Caragana arborescens"
    , "Carpenteria californica"
    , "Carpinus betulus"
    , "Carpinus betulus 'Quercifolia'"
    , "Carpinus caroliniana"
    , "Carpinus japonica"
    , "Carya cordiformis"
    , "Carya illinoinensis"
    , "Carya laciniosa"
    , "Carya ovata"
    , "Carya tomentosa"
    , "Cascabela thevetia"
    , "Cassia siberiana"
    , "Castanea crenata"
    , "Castanea sativa"
    , "Casuarina cunninghamiana"
    , "Casuarina stricta"
    , "Catalpa bignonioides"
    , "Catalpa bungei"
    , "Catalpa ovata"
    , "Catalpa speciosa"
    , "Catalpa x erubescens"
    , "Ceanothus x delilianus"
    , "Cedrus atlantica"
    , "Cedrus atlantica 'Glauca'"
    , "Cedrus brevifolia"
    , "Cedrus deodara"
    , "Cedrus deodara 'Paktia'"
    , "Cedrus libani"
    , "Ceiba speciosa"
    , "Celtis australis"
    , "Celtis occidentalis"
    , "Cephalanthus occidentalis"
    , "Cephalotaxus harringtonia"
    , "Cephalotaxus sinensis"
    , "Ceratonia siliqua"
    , "Cercidiphyllum japonicum"
    , "Cercis canadensis"
    , "Cercis chinensis"
    , "Cercis siliquastrum"
    , "Chaenomeles japonica"
    , "Chaenomeles speciosa"
    , "Chamaecyparis lawsoniana"
    , "Chamaecyparis pisifera"
    , "Chamaerops humilis"
    , "Chimonanthus praecox"
    , "Chionanthus retusus"
    , "Chionanthus virginicus"
    , "Chitalpa tashkentensis"
    , "Choisya ternata"
    , "Cinnamomum camphora"
    , "Cistus albidus"
    , "Cistus crispus"
    , "Cistus incanus"
    , "Cistus incanus ssp. creticus"
    , "Cistus ladanifer"
    , "Cistus laurifolius"
    , "Cistus monspeliensis"
    , "Cistus populifolius"
    , "Cistus salviifolius"
    , "Cistus symphytifolius"
    , "Citharexylum spinosum"
    , "Citrus x aurantium"
    , "Citrus x limon"
    , "Cladrastis kentukea"
    , "Clematis flammula"
    , "Clematis montana"
    , "Clematis vitalba"
    , "Clematis viticella"
    , "Clerodendrum trichotomum"
    , "Clethra alnifolia"
    , "Cneorum tricoccon"
    , "Coccoloba uvifera"
    , "Cocos nucifera"
    , "Colutea arborescens"
    , "Cornus alba"
    , "Cornus controversa"
    , "Cornus florida"
    , "Cornus kousa"
    , "Cornus mas"
    , "Cornus nuttallii"
    , "Cornus officinalis"
    , "Cornus racemosa"
    , "Cornus sanguinea"
    , "Cornus sericea"
    , "Corylopsis pauciflora"
    , "Corylopsis spicata"
    , "Corylopsis veitchiana"
    , "Corylus avellana"
    , "Corylus avellana 'Contorta'"
    , "Corylus colurna"
    , "Corylus maxima"
    , "Corymbia dallachiana"
    , "Cotinus coggygria"
    , "Cotoneaster dielsianus"
    , "Cotoneaster floccosus"
    , "Cotoneaster frigidus"
    , "Cotoneaster horizontalis"
    , "Cotoneaster integerrimus"
    , "Cotoneaster multiflorus"
    , "Crataegus laevigata"
    , "Crataegus laevigata 'Paul's Scarlet'"
    , "Crataegus monogyna"
    , "Crataegus nigra"
    , "Crataegus pedicellata"
    , "Crataegus pinnatifida"
    , "Crataegus succulenta var. macrantha"
    , "Crataegus x lavallei 'Carrierei'"
    , "Crataemespilus grandiflora"
    , "Cryptomeria japonica"
    , "Cryptomeria japonica f. cristata"
    , "Cunninghamia lanceolata"
    , "Cupressus arizonica"
    , "Cupressus glabra"
    , "Cupressus sempervirens"
    , "Cycas revoluta"
    , "Cydonia oblonga"
    , "Cytisus scoparius"
    , "Danae racemosa"
    , "Daphne gnidium"
    , "Daphne mezereum"
    , "Dasiphora fruticosa"
    , "Davidia involucrata"
    , "Decaisnea fargesii"
    , "Delonix regia"
    , "Deutzia longifolia"
    , "Deutzia scabra"
    , "Deutzia x hybrida"
    , "Diospyros kaki"
    , "Diospyros lotus"
    , "Dipelta floribunda"
    , "Distylium racemosum"
    , "Dracaena draco"
    , "Duranta erecta"
    , "Edgeworthia chrysantha"
    , "Ehretia dicksonii"
    , "Elaeagnus angustifolia"
    , "Elaeagnus pungens"
    , "Elaeagnus umbellata"
    , "Elaeagnus x ebbingei"
    , "Eleutherococcus sieboldianus"
    , "Erica arborea"
    ]


treesPart2 : List String
treesPart2 =
    [ "Eriobotrya japonica"
    , "Erythrina crista-galli"
    , "Eucalyptus globulus"
    , "Eucommia ulmoides"
    , "Euonymus alatus"
    , "Euonymus europaeus"
    , "Euonymus fortunei"
    , "Euonymus macropterus"
    , "Euonymus planipes"
    , "Exochorda giraldii"
    , "Fagus grandifolia"
    , "Fagus orientalis"
    , "Fagus sylvatica"
    , "Fagus sylvatica 'Asplenifolia'"
    , "Fagus sylvatica 'Felderbach'"
    , "Fagus sylvatica 'Pendula'"
    , "Fagus sylvatica 'Purpurea'"
    , "Fagus sylvatica 'Tortuosa'"
    , "Fagus sylvatica f. purpurea tricolor"
    , "Fatsia japonica"
    , "Feijoa sellowiana"
    , "Ficus benjamina"
    , "Ficus carica"
    , "Ficus lyrata"
    , "Ficus macrophylla"
    , "Ficus sycomorus"
    , "Firmiana simplex"
    , "Forsythia x intermedia"
    , "Fortunella"
    , "Fothergilla major"
    , "Frangula alnus"
    , "Fraxinus angustifolia"
    , "Fraxinus excelsior"
    , "Fraxinus excelsior f. diversifolia"
    , "Fraxinus latifolia"
    , "Fraxinus ornus"
    , "Fraxinus paxiana"
    , "Ginkgo biloba L."
    , "Gleditsia triacanthos"
    , "Grevillea robusta"
    , "Gymnocladus dioicus"
    , "Halesia carolina"
    , "Halesia monticola"
    , "Halimodendron halodendron"
    , "Hamamelis virginiana"
    , "Hamamelis x intermedia"
    , "Hedera helix"
    , "Heptacodium miconioides"
    , "Hibiscus rosa-sinensis"
    , "Hibiscus syriacus"
    , "Hippophae rhamnoides"
    , "Holodiscus discolor"
    , "Humulus lupulus"
    , "Hura crepitans"
    , "Hydrangea arborescens"
    , "Hydrangea aspera ssp. aspera"
    , "Hydrangea aspera ssp. sargentiana"
    , "Hydrangea macrophylla"
    , "Hydrangea paniculata"
    , "Hydrangea petiolaris"
    , "Hydrangea quercifolia"
    , "Hypericum androsaemum"
    , "Hypericum balearicum"
    , "Ilex aquifolium"
    , "Ilex crenata"
    , "Ilex pernyi"
    , "Jacaranda mimosifolia"
    , "Jasminum nudiflorum"
    , "Jasminum officinale"
    , "Juglans ailantifolia"
    , "Juglans cinerea"
    , "Juglans nigra"
    , "Juglans regia"
    , "Juniperus communis"
    , "Juniperus oxycedrus"
    , "Juniperus sabina"
    , "Juniperus scopulorum"
    , "Kalmia latifolia"
    , "Kerria japonica 'Pleniflora'"
    , "Khaya senegalensis"
    , "Koelreuteria paniculata"
    , "Kolkwitzia amabilis"
    , "Laburnum alpinum"
    , "Laburnum anagyroides"
    , "Lagerstroemia indica"
    , "Lagerstroemia speciosa"
    , "Lagunaria patersonia"
    , "Lantana camara"
    , "Larix decidua"
    , "Larix kaempferi"
    , "Larix x marschlinsii"
    , "Laurus nobilis"
    , "Lavandula angustifolia"
    , "Lavandula stoechas"
    , "Leucaena leucocephala"
    , "Leycesteria formosa"
    , "Ligustrum japonicum"
    , "Ligustrum lucidum"
    , "Ligustrum ovalifolium"
    , "Ligustrum vulgare"
    , "Liquidambar formosana"
    , "Liquidambar orientalis"
    , "Liquidambar styraciflua"
    , "Liriodendron chinense"
    , "Liriodendron tulipifera"
    , "Lonicera caprifolium"
    , "Lonicera etrusca"
    , "Lonicera henryi"
    , "Lonicera implexa"
    , "Lonicera kamtschatica"
    , "Lonicera maackii"
    , "Lonicera nigra"
    , "Lonicera periclymenum"
    , "Lonicera pileata"
    , "Lonicera tatarica"
    , "Lonicera x heckrottii"
    , "Lonicera x purpusii 'Winter Beauty'"
    , "Lonicera xylosteum"
    , "Lycium barbarum"
    , "Maclura pomifera"
    , "Magnolia acuminata"
    , "Magnolia denudata"
    , "Magnolia grandiflora"
    , "Magnolia kobus"
    , "Magnolia liliiflora"
    , "Magnolia obovata"
    , "Magnolia sieboldii"
    , "Magnolia stellata"
    , "Magnolia tripetala"
    , "Magnolia x soulangeana"
    , "Magnolia x wiesneri"
    , "Mahonia aquifolium"
    , "Mahonia x media"
    , "Malus domestica"
    , "Malus floribunda"
    , "Malus sargentii"
    , "Malus sylvestris"
    , "Malus toringoides"
    , "Malus x purpurea"
    , "Melia azedarach"
    , "Mespilus germanica"
    , "Metasequoia glyptostroboides"
    , "Morus alba"
    , "Morus alba f. macrophylla"
    , "Morus nigra"
    , "Myoporum serratum"
    , "Myrtus communis"
    , "Nandina domestica"
    , "Nerium oleander"
    , "Nicotiana glauca"
    , "Nothofagus antarctica"
    , "Nyssa sylvatica"
    , "Olea europaea"
    , "Osmanthus x burkwoodii"
    , "Osmanthus x fortunei"
    , "Ostrya carpinifolia"
    , "Ostrya virginiana"
    , "Osyris alba"
    , "Oxydendrum arboreum"
    , "Pachypodium lamerei"
    , "Paeonia x suffruticosa"
    , "Paliurus spina-christi"
    , "Parkinsonia aculeata"
    , "Parrotia persica"
    , "Parrotiopsis jaquemontiana"
    , "Parthenocissus inserta"
    , "Parthenocissus quinquefolia"
    , "Parthenocissus tricuspidata"
    , "Passiflora caerulea"
    , "Paulownia tomentosa"
    , "Peltophorum pterocarpum"
    , "Pereskia bleo"
    , "Persea americana"
    , "Petteria ramentacea"
    , "Phellodendron amurense"
    , "Philadelphus coronarius"
    , "Philadelphus x virginalis"
    , "Phillyrea angustifolia"
    , "Phillyrea latifolia"
    , "Phoenix canariensis"
    , "Phoenix dactylifera"
    , "Photinia davidiana"
    , "Photinia x fraseri"
    , "Physocarpus opulifolius"
    , "Phytolacca dioica"
    , "Picea abies"
    , "Picea abies 'Inversa'"
    , "Picea asperata"
    , "Picea breweriana"
    , "Picea engelmanii"
    , "Picea glauca"
    , "Picea glauca 'Conica'"
    , "Picea mariana"
    , "Picea omorika"
    , "Picea orientalis"
    , "Picea polita"
    , "Picea pungens 'Glauca'"
    , "Picea sitchensis"
    , "Picea wilsonii"
    ]


treesPart3 : List String
treesPart3 =
    [ "Pieris floribunda"
    , "Pieris japonica"
    , "Pinus aristata"
    , "Pinus armandii"
    , "Pinus attenuata"
    , "Pinus banksiana"
    , "Pinus bungeana"
    , "Pinus canariensis"
    , "Pinus cembra"
    , "Pinus contorta"
    , "Pinus coulteri"
    , "Pinus halepensis"
    , "Pinus heldreichii"
    , "Pinus jeffreyi"
    , "Pinus koraiensis"
    , "Pinus leucodermis"
    , "Pinus monticola"
    , "Pinus mugo"
    , "Pinus nigra"
    , "Pinus nigra var. laricio"
    , "Pinus nigra var. salzmanii"
    , "Pinus parviflora"
    , "Pinus peuce"
    , "Pinus pinaster"
    , "Pinus pinea"
    , "Pinus ponderosa"
    , "Pinus strobus"
    , "Pinus sylvestris"
    , "Pinus thunbergii"
    , "Pinus wallichiana"
    , "Pistacia lentiscus"
    , "Pistacia terebinthus"
    , "Pistacia vera"
    , "Pittosporum tobira"
    , "Platanus orientalis"
    , "Platanus x hispanica"
    , "Platycarya strobilacea"
    , "Platycladus orientalis"
    , "Plumbago auriculata"
    , "Plumeria rubra"
    , "Podranea ricasoliana"
    , "Polygala myrtifolia"
    , "Poncirus trifoliata"
    , "Populus alba"
    , "Populus balsamifera"
    , "Populus nigra"
    , "Populus nigra 'Italica'"
    , "Populus simonii"
    , "Populus tremula"
    , "Populus x canadensis"
    , "Populus x canescens"
    , "Prosopis juliflora"
    , "Prunus 'Accolade'"
    , "Prunus 'Kursar'"
    , "Prunus armeniaca"
    , "Prunus avium"
    , "Prunus avium 'Plena'"
    , "Prunus cerasifera"
    , "Prunus cerasifera 'Nigra'"
    , "Prunus cerasifera 'Rosea'"
    , "Prunus cerasus"
    , "Prunus cerasus 'Rhexii'"
    , "Prunus davidiana"
    , "Prunus domestica"
    , "Prunus domestica ssp. insititia"
    , "Prunus domestica ssp. syriaca"
    , "Prunus domestica subsp. domestica"
    , "Prunus domestica subsp. italica"
    , "Prunus dulcis"
    , "Prunus fenziliana"
    , "Prunus incana"
    , "Prunus incisa"
    , "Prunus laurocerasus"
    , "Prunus lusitanica"
    , "Prunus maackii"
    , "Prunus mahaleb"
    , "Prunus mume"
    , "Prunus nipponica var. kurilensis"
    , "Prunus padus"
    , "Prunus persica"
    , "Prunus sargentii"
    , "Prunus serotina"
    , "Prunus serrula"
    , "Prunus serrulata 'Kanzan'"
    , "Prunus sibirica"
    , "Prunus spinosa"
    , "Prunus subhirtella"
    , "Prunus subhirtella f. autumnalis"
    , "Prunus tomentosa"
    , "Prunus triloba"
    , "Pseudocydonia sinensis"
    , "Pseudolarix amabilis"
    , "Pseudotsuga menziesii"
    , "Ptelea trifoliata"
    , "Pterocarya fraxinifolia"
    , "Pterocarya stenoptera"
    , "Pterostyrax corymbosus"
    , "Pterostyrax hispidus"
    , "Punica granatum"
    , "Pyracantha coccinea"
    , "Pyrus betulifolia"
    , "Pyrus calleryana 'Chanticleer'"
    , "Pyrus communis"
    , "Pyrus pyraster"
    , "Pyrus pyrifolia var. culta"
    , "Pyrus salicifolia"
    , "Quercus acutissima"
    , "Quercus alba"
    , "Quercus canariensis"
    , "Quercus castaneifolia"
    , "Quercus cerris"
    , "Quercus coccifera"
    , "Quercus coccinea"
    , "Quercus dentata"
    , "Quercus faginea"
    , "Quercus frainetto"
    , "Quercus ilex"
    , "Quercus ilicifolia"
    , "Quercus imbricaria"
    , "Quercus libani"
    , "Quercus macranthera"
    , "Quercus macrocarpa"
    , "Quercus marilandica"
    , "Quercus palustris"
    , "Quercus petraea"
    , "Quercus petraea 'Laciniata Crispa'"
    , "Quercus phellos"
    , "Quercus pontica"
    , "Quercus pubescens"
    , "Quercus pyrenaica"
    , "Quercus robur"
    , "Quercus robur 'Pectinata'"
    , "Quercus robur f. fastigiata"
    , "Quercus rubra"
    , "Quercus shumardii"
    , "Quercus suber"
    , "Quercus velutina"
    , "Quercus x hispanica 'Lucombeana'"
    , "Quercus x turneri"
    , "Rhamnus alaternus"
    , "Rhamnus cathartica"
    , "Rhamnus imeretina"
    , "Rhamnus lycioides"
    , "Rhamnus pumila"
    , "Rhamnus saxatilis"
    , "Rhododendron catawbiense"
    , "Rhododendron tomentosum"
    , "Rhodotypos scandens"
    , "Rhus typhina"
    , "Ribes aureum"
    , "Ribes rubrum"
    , "Ribes sanguineum"
    , "Ribes uva-crispa var. sativum"
    , "Ricinus communis"
    , "Robinia hispida"
    , "Robinia luxurians"
    , "Robinia pseudoacacia"
    , "Robinia x margaretta 'Casque Rouge'"
    , "Rosa canina"
    , "Rosa rugosa"
    , "Rosa spinosissima"
    , "Rosa tomentosa"
    , "Rubia peregrina"
    , "Rubus fruticosus"
    , "Rubus idaeus"
    , "Rubus odoratus"
    , "Rubus spectabilis"
    , "Ruscus aculeatus"
    , "Salix alba"
    , "Salix alba 'Tristis'"
    , "Salix aurita"
    , "Salix babylonica"
    , "Salix caprea"
    , "Salix caprea 'Kilmarnock'"
    , "Salix cinerea"
    , "Salix fragilis"
    , "Salix integra 'Hakuro Nishiki'"
    , "Salix irrorata"
    , "Salix matsudana 'Tortuosa'"
    , "Salix purpurea"
    , "Salix udensis f. sekka"
    , "Salix viminalis"
    , "Samanea saman"
    , "Sambucus nigra"
    , "Sambucus nigra ssp. caerulea"
    , "Sambucus racemosa"
    , "Sarcococca hookeriana var. humilis"
    , "Sassafras albidum"
    , "Schefflera actinophylla"
    , "Schinus molle"
    , "Sciadopitys verticillata"
    , "Senna didymobotrya"
    , "Senna x floribunda"
    , "Sequoia sempervirens"
    , "Sequoiadendron giganteum"
    , "Shepherdia argentea"
    , "Sinocalycanthus chinensis"
    , "Skimmia japonica"
    , "Smilax aspera"
    , "Solanum dulcamara"
    , "Solanum jasminoides"
    , "Sorbaria sorbifolia"
    , "Sorbus alnifolia"
    , "Sorbus americana"
    , "Sorbus aria"
    , "Sorbus aucuparia"
    , "Sorbus domestica"
    , "Sorbus intermedia"
    , "Sorbus torminalis"
    , "Spartium junceum"
    , "Spathodea campanulata"
    , "Spiraea japonica"
    , "Spiraea thunbergii"
    , "Spiraea x billardii"
    , "Spiraea x vanhouttei"
    , "Stachyurus praecox"
    , "Staphylea colchica"
    , "Staphylea holocarpa"
    , "Staphylea pinnata"
    , "Stewartia pseudocamellia"
    , "Styphnolobium japonicum"
    , "Styrax japonicus"
    , "Styrax obassia"
    , "Symphoricarpos albus"
    , "Symphoricarpos x chenaultii"
    , "Syringa reflexa"
    , "Syringa vulgaris"
    , "Taiwania cryptomerioides"
    , "Tamarix parviflora"
    , "Taxodium distichum"
    , "Taxus baccata"
    , "Tecoma capensis"
    , "Tecoma stans"
    , "Terminalia catappa"
    , "Tetradium daniellii"
    , "Thuja occidentalis"
    , "Thuja plicata"
    , "Thujopsis dolabrata"
    , "Thymelaea hirsuta"
    , "Tilia americana"
    , "Tilia cordata"
    , "Tilia dasystyla"
    , "Tilia henryana"
    , "Tilia mongolica"
    , "Tilia platyphyllos"
    , "Tilia tomentosa"
    , "Tilia tomentosa f. petiolaris"
    , "Tilia x euchlora"
    , "Tilia x europaea"
    , "Tipuana tipu"
    , "Toona sinensis"
    , "Trachycarpus fortunei"
    , "Tsuga canadensis"
    , "Tsuga diversifolia"
    , "Tsuga heterophylla"
    , "Ulex europaeus"
    , "Ulmus glabra"
    , "Ulmus laevis"
    , "Ulmus minor"
    , "Ulmus minor 'Jacqueline Hillier'"
    , "Ulmus minor 'Wredei'"
    , "Ulmus parvifolia"
    , "Ulmus pumila"
    , "Vaccinium myrtillus"
    , "Vaccinium uliginosum"
    , "Vaccinium vitis-idaea"
    , "Vachellia xanthophloea"
    , "Viburnum davidii"
    , "Viburnum farreri"
    , "Viburnum lantana"
    , "Viburnum lantanoides"
    , "Viburnum lentago"
    , "Viburnum opulus"
    , "Viburnum opulus f. roseum"
    , "Viburnum plicatum"
    , "Viburnum plicatum f. sterile"
    , "Viburnum rhytidophyllum"
    , "Viburnum tinus"
    , "Viburnum x bodnantense"
    , "Viburnum x burkwoodii"
    , "Viburnum x carlcephalum"
    , "Viscum album"
    , "Vitex agnus-castus"
    , "Vitis coignetiae"
    , "Vitis vinifera"
    , "Washingtonia filifera"
    , "Washingtonia robusta"
    , "Weigela florida"
    , "Wisteria sinensis"
    , "Wollemia nobilis"
    , "Xanthocyparis nootkatensis"
    , "Zanthoxylum simulans"
    , "Zelkova carpinifolia"
    , "Zelkova serrata"
    , "Ziziphus jujuba"
    ]
