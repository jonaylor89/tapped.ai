// Mirrors com.intheloopstudio/lib/domains/models/genre.dart (JSON values are the Firestore values).

public enum Genre: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case pop
    case hipHop
    case electronic
    case rnb
    case rock
    case metal
    case funk
    case jazz
    case punk
    case psychedelia
    case afrobeat
    case aggrotech
    case ambient
    case ambientPop
    case americana
    case axe = "axé"
    case bachata
    case baiao = "baião"
    case ballet
    case blackenedCrust
    case blues
    case bolero
    case bossaNova
    case bounce
    case bregaCalypso
    case britpop
    case calypso
    case chanson
    case childrensMusic
    case christmas
    case classical
    case classicalCrossover
    case comedy
    case country
    case cumbia
    case dBeat
    case dance
    case dancehall
    case darkwave
    case deathIndustrial
    case dembow
    case driftPhonk
    case drone
    case dungeonSynth
    case easyListening
    case emo
    case epicCollage
    case etherealWave
    case exotica
    case experimental
    case fieldRecordings
    case flamenco
    case flamencoPop
    case folk
    case forro = "forró"
    case frevo
    case funkBrasileiro
    case futurepop
    case gamelan
    case glitchPop
    case gospel
    case gregorianChant
    case grunge
    case hymns
    case hyperpop
    case hypnagogicPop
    case indiePop
    case industrial
    case janglePop
    case juke
    case klezmer
    case latinAlternative
    case liquidDrumAndBass
    case mambo
    case mandeMusic
    case maracatu
    case mariachi
    case mashup
    case minimalSynth
    case modaDeViola
    case mpb
    case musicalParody
    case musiqueConcrete = "musiqueConcrète"
    case neoMedievalFolk
    case neoclassicalDarkwave
    case newAge
    case newRave
    case noise
    case noisePop
    case noisegrind
    case nwobhm
    case pianoRock
    case plunderphonics
    case polka
    case postHardcore
    case postMinimalism
    case postPunk
    case powerElectronics
    case powerPop
    case progressivePop
    case psichedeliaOccultaItaliana
    case psychobilly
    case radioDrama
    case ragtime
    case rapRock
    case reggae
    case reggaeton
    case regional
    case rockAndRoll
    case rockabilly
    case salsa
    case samba
    case sampledelia
    case seaShanties
    case sertanejo
    case sertanejoDeRaiz
    case sertanejoUniversitario = "sertanejoUniversitário"
    case showTunes
    case sierreno = "sierreño"
    case singerSongwriter
    case ska
    case spokenWord
    case standards
    case surfPop
    case synthFunk
    case synthPunk
    case tango
    case tishoumaren
    case totalism
    case tweePop
    case vanguardaPaulista
    case vapor
    case xote
    case yeYe = "yéYé"
    case `other`

    public var id: String { rawValue }

    public var formattedName: String {
        switch self {
        case .pop: "Pop"
        case .hipHop: "Hip Hop"
        case .electronic: "Electronic"
        case .rnb: "R&B"
        case .rock: "Rock"
        case .metal: "Metal"
        case .funk: "Funk"
        case .jazz: "Jazz"
        case .punk: "Punk"
        case .psychedelia: "Psychedelia"
        case .afrobeat: "Afrobeat"
        case .aggrotech: "Aggrotech"
        case .ambient: "Ambient"
        case .ambientPop: "Ambient Pop"
        case .americana: "Americana"
        case .axe: "Axé"
        case .bachata: "Bachata"
        case .baiao: "Baião"
        case .ballet: "Ballet"
        case .blackenedCrust: "Blackened Crust"
        case .blues: "Blues"
        case .bolero: "Bolero"
        case .bossaNova: "Bossa Nova"
        case .bounce: "Bounce"
        case .bregaCalypso: "Brega Calypso"
        case .britpop: "Britpop"
        case .calypso: "Calypso"
        case .chanson: "Chanson"
        case .childrensMusic: "Children's Music"
        case .christmas: "Christmas"
        case .classical: "Classical"
        case .classicalCrossover: "Classical Crossover"
        case .comedy: "Comedy"
        case .country: "Country"
        case .cumbia: "Cumbia"
        case .dBeat: "D-Beat"
        case .dance: "Dance"
        case .dancehall: "Dancehall"
        case .darkwave: "Darkwave"
        case .deathIndustrial: "Death Industrial"
        case .dembow: "Dembow"
        case .driftPhonk: "Drift Phonk"
        case .drone: "Drone"
        case .dungeonSynth: "Dungeon Synth"
        case .easyListening: "Easy Listening"
        case .emo: "Emo"
        case .epicCollage: "Epic Collage"
        case .etherealWave: "Ethereal Wave"
        case .exotica: "Exotica"
        case .experimental: "Experimental"
        case .fieldRecordings: "Field Recordings"
        case .flamenco: "Flamenco"
        case .flamencoPop: "Flamenco Pop"
        case .folk: "Folk"
        case .forro: "Forró"
        case .frevo: "Frevo"
        case .funkBrasileiro: "Funk Brasileiro"
        case .futurepop: "Futurepop"
        case .gamelan: "Gamelan"
        case .glitchPop: "Glitch Pop"
        case .gospel: "Gospel"
        case .gregorianChant: "Gregorian Chant"
        case .grunge: "Grunge"
        case .hymns: "Hymns"
        case .hyperpop: "Hyperpop"
        case .hypnagogicPop: "Hypnagogic Pop"
        case .indiePop: "Indie Pop"
        case .industrial: "Industrial"
        case .janglePop: "Jangle Pop"
        case .juke: "Juke"
        case .klezmer: "Klezmer"
        case .latinAlternative: "Latin Alternative"
        case .liquidDrumAndBass: "Liquid Drum and Bass"
        case .mambo: "Mambo"
        case .mandeMusic: "Mande Music"
        case .maracatu: "Maracatu"
        case .mariachi: "Mariachi"
        case .mashup: "Mashup"
        case .minimalSynth: "Minimal Synth"
        case .modaDeViola: "Moda de Viola"
        case .mpb: "MPB"
        case .musicalParody: "Musical Parody"
        case .musiqueConcrete: "Musique Concrète"
        case .neoMedievalFolk: "Neo-Medieval Folk"
        case .neoclassicalDarkwave: "Neoclassical Darkwave"
        case .newAge: "New Age"
        case .newRave: "New Rave"
        case .noise: "Noise"
        case .noisePop: "Noise Pop"
        case .noisegrind: "Noisegrind"
        case .nwobhm: "NWOBHM"
        case .pianoRock: "Piano Rock"
        case .plunderphonics: "Plunderphonics"
        case .polka: "Polka"
        case .postHardcore: "Post-Hardcore"
        case .postMinimalism: "Post-Minimalism"
        case .postPunk: "Post-Punk"
        case .powerElectronics: "Power Electronics"
        case .powerPop: "Power Pop"
        case .progressivePop: "Progressive Pop"
        case .psichedeliaOccultaItaliana: "Psichedelia Occulta Italiana"
        case .psychobilly: "Psychobilly"
        case .radioDrama: "Radio Drama"
        case .ragtime: "Ragtime"
        case .rapRock: "Rap Rock"
        case .reggae: "Reggae"
        case .reggaeton: "Reggaeton"
        case .regional: "Regional"
        case .rockAndRoll: "Rock & Roll"
        case .rockabilly: "Rockabilly"
        case .salsa: "Salsa"
        case .samba: "Samba"
        case .sampledelia: "Sampledelia"
        case .seaShanties: "Sea Shanties"
        case .sertanejo: "Sertanejo"
        case .sertanejoDeRaiz: "Sertanejo de Raiz"
        case .sertanejoUniversitario: "Sertanejo Universitário"
        case .showTunes: "Show Tunes"
        case .sierreno: "Sierreño"
        case .singerSongwriter: "Singer-Songwriter"
        case .ska: "Ska"
        case .spokenWord: "Spoken Word"
        case .standards: "Standards"
        case .surfPop: "Surf Pop"
        case .synthFunk: "Synth Funk"
        case .synthPunk: "Synth Punk"
        case .tango: "Tango"
        case .tishoumaren: "Tishoumaren"
        case .totalism: "Totalism"
        case .tweePop: "Twee Pop"
        case .vanguardaPaulista: "Vanguarda Paulista"
        case .vapor: "Vapor"
        case .xote: "Xote"
        case .yeYe: "Yé-yé"
        case .other: "Other"
        }
    }
}
