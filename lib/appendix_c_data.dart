// appendix_c_data.dart
//
// Static reference data for ARPL Toolkit "Appendix C: Trade Curriculum
// Content Summary". This is read-only note content — no DB round trip
// needed. Add new trades by adding another entry to [appendixCData] keyed
// by OFO number.

/// A single bullet row in a curriculum category, e.g.
/// "Knowledge of Trade related tools and machinery" with its
/// indented "> Spanners / Screw drivers / ..." sub-items.
class CurriculumBullet {
  final String text;
  final List<String> subItems;

  const CurriculumBullet(this.text, [this.subItems = const []]);
}

/// A boxed section in the Appendix C table, e.g. "SAFETY",
/// "HAND, POWER AND WORKSHOP TOOLS", "SITE ASSESSMENT".
class CurriculumCategory {
  final String title;
  final List<CurriculumBullet> bullets;

  const CurriculumCategory(this.title, this.bullets);
}

/// OFO numbers -> friendly trade name. Used for detection/display and to
/// keep a single source of truth between the OFO code and the label shown
/// in the UI. Extend this as you register more trades.
const Map<String, String> ofoTradeNames = {
  '641201': 'Bricklayer',
  '642601': 'Plumber',
  '671101': 'Electrician',
};

/// Common synonyms/aliases seen in learner/pathway records, mirroring the
/// trade-name synonym matching already used for pathway detection
/// (see ArplAssessorPage.dart pathway lookup). Lower-cased for matching.
const Map<String, String> tradeNameSynonymsToOfo = {
  'bricklayer': '641201',
  'bricklaying': '641201',
  'brick layer': '641201',
  'plumber': '642601',
  'plumbing': '642601',
  'electrician': '671101',
  'electrical': '671101',
};

/// Resolves an OFO number from either an OFO code or a free-text trade
/// name pulled from learner/pathway data. Returns null if no match.
String? resolveOfoNumber({String? ofoNumber, String? tradeName}) {
  if (ofoNumber != null && ofoTradeNames.containsKey(ofoNumber)) {
    return ofoNumber;
  }
  if (tradeName != null) {
    final key = tradeName.trim().toLowerCase();
    if (tradeNameSynonymsToOfo.containsKey(key)) {
      return tradeNameSynonymsToOfo[key];
    }
    // fallback: partial match (e.g. "ARPL Bricklaying Assessor")
    for (final entry in tradeNameSynonymsToOfo.entries) {
      if (key.contains(entry.key)) return entry.value;
    }
  }
  return null;
}

/// Appendix C content, keyed by OFO number.
final Map<String, List<CurriculumCategory>> appendixCData = {
  // ---------------------------------------------------------------------
  // PLUMBER — OFO 642601 (transcribed from the toolkit Appendix C pages)
  // ---------------------------------------------------------------------
  '642601': const [
    CurriculumCategory('SAFETY', [
      CurriculumBullet(
          'Standard construction industry safety principles and concepts'),
      CurriculumBullet('First Aid application and awareness'),
      CurriculumBullet(
          'Identify different colour markings and symbolic safety signs'),
      CurriculumBullet(
          'Risk assessment theories and principals and application thereof'),
    ]),
    CurriculumCategory('HAND, POWER AND WORKSHOP TOOLS', [
      CurriculumBullet('Knowledge of Trade related tools and machinery', [
        'Spanners',
        'Screw drivers',
        'Hammer and chisel',
        'Saws and grinders',
        'Knowledge of Trade related Tin-snips (left, right and straight)',
        'Drilling machine',
        'Pipe threader (manual and machine)',
        'Forming/rolling machine',
        'Guillotine',
      ]),
      CurriculumBullet('Correct use and care thereof'),
    ]),
    CurriculumCategory('MEASURING EQUIPMENT', [
      CurriculumBullet('Knowledge of Trade related measuring equipment', [
        'Measuring tape and steel rule',
        'Spirit level',
        'Dumpy Level and Staff',
        'Callipers (inside and outside)',
        'Compass and divider',
        'Pressure tester',
        'Chalk line',
      ]),
      CurriculumBullet('Correct use and care thereof'),
    ]),
    CurriculumCategory('PLANS AND DRAWINGS', [
      CurriculumBullet('Read and interpret Trade related plans and drawings', [
        'Terms and definitions',
        'Signs and symbols',
        'Material lists',
        'Orientation and levels',
        'Existing services',
      ]),
    ]),
    CurriculumCategory('IDENTIFICATION OF PIPE AND FITTINGS', [
      CurriculumBullet(
          'Understand the physical properties and characteristics of various pipe and fittings',
          [
            'Copper',
            'uPVC',
            'Galvanised Mild steel',
            'HDPE',
            'Cast Iron',
            'Pex',
            'Plastic',
          ]),
      CurriculumBullet('Correct use and application of the different types thereof'),
      CurriculumBullet('Appearances and finishes'),
    ]),
    CurriculumCategory('SANITARY WARE', [
      CurriculumBullet('Knowledge of trade related sanitary ware products'),
      CurriculumBullet('Understanding of correct installation methods thereof'),
    ]),
    CurriculumCategory('TRANSPORTATION, HANDLING AND STORAGE OF MATERIALS', [
      CurriculumBullet(
          'Knowledge of safe transportation, handling and storage of Trade related materials'),
    ]),
    CurriculumCategory('ACCESS EQUIPMENT', [
      CurriculumBullet('Knowledge of Trade related access equipment', [
        'Ladders',
        'Scaffolding',
      ]),
    ]),
    CurriculumCategory('HOT WATER SYSTEM', [
      CurriculumBullet('Knowledge of Hot water system'),
      CurriculumBullet('Water storage tank'),
    ]),
    CurriculumCategory('COLD WATER SYSTEM', [
      CurriculumBullet('Knowledge of Cold water systems'),
      CurriculumBullet('Water storage tank'),
    ]),
    CurriculumCategory('RAIN WATER SYSTEM', [
      CurriculumBullet('Knowledge of Rain water systems'),
      CurriculumBullet('Rain water storage tank'),
      CurriculumBullet('Fabrication of gutters, downpipes and flashing'),
      CurriculumBullet('Installation of gutters, downpipes and flashing'),
    ]),
    CurriculumCategory('ABOVE GROUND DRAINAGE SYSTEM', [
      CurriculumBullet('Knowledge of above ground drainage systems', [
        'Gradients',
        'Branches',
        'Vents',
        'Traps',
        'Access',
        'Rodding eye',
      ]),
    ]),
    CurriculumCategory('BELOW GROUND DRAINAGE SYSTEM', [
      CurriculumBullet('Knowledge of below ground drainage systems', [
        'Gradients',
        'Gullies',
        'Manholes',
        'Access',
        'Rodding eyes',
        'Floor drains',
      ]),
    ]),
    CurriculumCategory('SANS CODES AND NATIONAL BUILDING REGULATIONS', [
      CurriculumBullet(
          'Application of SANS Codes and National Building Regulations', [
        'SANS 10400',
        'SANS 10252',
        'SANS 10254',
        'Municipal by-laws',
      ]),
    ]),
    CurriculumCategory('SANITARY WARE APPLIANCES', [
      CurriculumBullet('Knowledge of available appliances', [
        'Baths',
        'Basins',
        'Sinks',
        'Showers',
        'Bidets',
        'Water closet',
        'Urinals',
        'Washing Machines',
        'Taps',
        'Fixtures',
      ]),
      CurriculumBullet(
          'Characteristics of different materials used in manufacture thereof'),
    ]),
    CurriculumCategory('TRENCHING AND BACKFILL', [
      CurriculumBullet('Knowledge of trenching and backfilling', [
        'Regulations',
        'Marking and digging',
        'Shoring',
        'Backfill material',
        'Compacting',
      ]),
    ]),
    CurriculumCategory('BASIC BUILDING WORKS', [
      CurriculumBullet('Knowledge of basic building works', [
        'Wall chasing',
        'Manhole',
        'Mortar mixes',
        'Inspection chamber',
      ]),
    ]),
    CurriculumCategory('VALVES AND TERMINAL FIXTURES', [
      CurriculumBullet('Knowledge of valves and terminal fixtures', [
        'Pressure control valve',
        'One way valve',
        'Flow control valve',
        'TP valve',
        'Expansion control / relief valve',
        'Isolation valves',
        'Automatic sensor taps',
        'Gate valves',
        'Bib taps',
        'Mixer taps',
        'Water level valves',
        'Water and sewage Pumps',
      ]),
      CurriculumBullet('Correct use, installation and maintenance thereof'),
    ]),
    CurriculumCategory('HYDRAULIC LOADING AND AIR TEST', [
      CurriculumBullet('Knowledge of hydraulic loading', [
        'Correct calculation',
        'Effects of overloading',
        'Flow velocities',
      ]),
      CurriculumBullet('Knowledge of pressure air testing', [
        'Setting up',
        'Reading measurements',
        'Corrective action',
      ]),
    ]),
    CurriculumCategory('INSTALL AND READ OF WATER METERS', [
      CurriculumBullet('Knowledge to install and test water meters', [
        'Who installs?',
        'Where are they installed?',
        'Different types',
      ]),
    ]),
    CurriculumCategory('BRAZING AND SOLDERING', [
      CurriculumBullet('Knowledge of brazing and soldering', [
        'Fluxes',
        'Reaction of metals to the weather and chemicals',
        'When to braze',
        'When to solder',
        'Use of different flame types',
        'In confined spaces',
      ]),
    ]),
    CurriculumCategory('JOINTING AND INSTALLING OF PIPING', [
      CurriculumBullet('Knowledge of characteristics of pipe and fittings', [
        'Identify different classes of pipe and their application',
        'Expansion and contraction of pipework',
        'Protection from adverse environments',
        'When to use screwed, capillary and compression joints',
      ]),
    ]),
    CurriculumCategory('SITE ASSESSMENT', [
      CurriculumBullet('Knowledge of how to conduct a site assessment', [
        'Orientation of site',
        'Position of services',
        'Position of sanitary ware',
        'Position of wastes and drains',
        'Liaising with main contractor',
      ]),
    ]),
    CurriculumCategory('RISK ASSESSMENT', [
      CurriculumBullet('Knowledge of how to conduct a risk assessment', [
        'Reduce to writing',
        'Use of a checklist',
        'Safety file',
        'Training',
        'Inspections',
        'Certifications',
      ]),
    ]),
    CurriculumCategory('SEPTIC TANK', [
      CurriculumBullet(
          'Knowledge of the installation and maintenance of a septic tank', [
        'Excavation',
        'Building / installation of pre-cast tank',
        'Invert levels',
        'Access points',
        'Backfilling',
        'Compacting',
        'Site clearing',
        'Commissioning',
        'Maintenance',
      ]),
    ]),
    CurriculumCategory('SHEET METAL', [
      CurriculumBullet('Knowledge of sheet metal fabrication', [
        'Different types of joints',
        'Templates',
        'Developments',
        'Cutting and shaping',
      ]),
      CurriculumBullet('Correct use of tools'),
    ]),
  ],

  // ---------------------------------------------------------------------
  // ELECTRICIAN — OFO 671101 (transcribed from the toolkit Appendix C
  // "Trade Curriculum Content Summary" pages, Trade Overview table)
  // ---------------------------------------------------------------------
  '671101': const [
    CurriculumCategory('HEALTH, SAFETY, QUALITY AND LEGISLATION', [
      CurriculumBullet(
          'Legislation and regulations for workplace safety within electricity'),
      CurriculumBullet('Safety symbols and colour coding'),
      CurriculumBullet(
          'Fundamentals of isolating and locking out equipment and circuits'),
      CurriculumBullet('Hazard identification and risk principles'),
      CurriculumBullet(
          'Environmental, protection and pollution concepts'),
    ]),
    CurriculumCategory('TOOLS, EQUIPMENT AND MATERIALS', [
      CurriculumBullet('Types, uses and care of hand tools'),
      CurriculumBullet('Types, uses and care of portable power tools'),
      CurriculumBullet('Types, uses and care of fixed power tools'),
    ]),
    CurriculumCategory(
        'INTRODUCTION TO THE WORLD OF WORK AND THE ELECTRICAL TRADE', [
      CurriculumBullet('The Electricians world of work'),
      CurriculumBullet('Career opportunities of qualified Electricians'),
      CurriculumBullet("The Electrician's responsibilities and duties"),
      CurriculumBullet(
          'Legislation relating to apprentices in the Electrical trade'),
      CurriculumBullet('Trade test requirements'),
    ]),
    CurriculumCategory('MEASURING AND TESTING INSTRUMENTS', [
      CurriculumBullet(
          'Types of electrical measuring and testing instruments'),
      CurriculumBullet('Safe use of measuring and testing instruments'),
      CurriculumBullet(
          'Construction and operating principles of measuring and testing instruments'),
      CurriculumBullet(
          'Methods of connecting measuring and testing instruments in circuits'),
      CurriculumBullet(
          'Applications and methods of using electrical measuring and testing instruments'),
      CurriculumBullet(
          'Care and maintenance of single and three phase measuring and testing instruments'),
      CurriculumBullet('Instrument transformers'),
    ]),
    CurriculumCategory('FUNDAMENTALS OF ELECTRICITY', [
      CurriculumBullet('Principles and fundamental concepts of electricity'),
      CurriculumBullet(
          'Definitions, types, properties and applications of conductors, insulators and semi-conductors'),
      CurriculumBullet(
          'Concepts, theories and principles of Electrical Circuits'),
      CurriculumBullet(
          'Calculations on basic electrical circuits (resistance, voltage and current) and power'),
      CurriculumBullet(
          'Basic principles and calculation of magnetism'),
    ]),
    CurriculumCategory('ELECTRONICS', [
      CurriculumBullet(
          'International Electro technical Commission (IEC) symbols for electronic components'),
      CurriculumBullet(
          'Principles, safety precautions, identification and basic function of electronic components'),
      CurriculumBullet('Basic electronic circuits'),
      CurriculumBullet(
          'Principles of rectification, single phase and 3-phase'),
    ]),
    CurriculumCategory('WIRE WAYS AND WIRING', [
      CurriculumBullet(
          'Definition, types, purpose and applications of wire ways'),
      CurriculumBullet(
          'Regulations and statutory requirements for wiring of premises'),
      CurriculumBullet('Electrical diagrams and symbols'),
      CurriculumBullet('Electrical components and their applications'),
    ]),
    CurriculumCategory('AC MOTORS', [
      CurriculumBullet('Construction of alternating current motors'),
      CurriculumBullet('Principle of operation of alternating current motors'),
      CurriculumBullet('Configuration of motor connections'),
      CurriculumBullet(
          'Types of single phase and three phase alternating current motors'),
      CurriculumBullet(
          'Testing principles of single phase and three phase alternating current motors'),
    ]),
    CurriculumCategory('DC MOTORS', [
      CurriculumBullet('Construction of direct current motors'),
      CurriculumBullet('Principle of operation of direct current motors'),
      CurriculumBullet('Types of single direct current motors'),
      CurriculumBullet('Application of alternating current motors'),
      CurriculumBullet('Testing principles of direct current motors'),
    ]),
    CurriculumCategory('ALTERNATORS AND GENERATORS', [
      CurriculumBullet('Construction of alternators and generators'),
      CurriculumBullet(
          'Principle of operation of alternators and generators'),
      CurriculumBullet(
          'Configuration of alternator and generator connections'),
      CurriculumBullet('Types and application of alternators and generators'),
      CurriculumBullet('Testing principles of alternators and generators'),
      CurriculumBullet('Protection of alternators and generators'),
      CurriculumBullet('Calculate properties of alternators and generators'),
    ]),
    CurriculumCategory('ELECTRICAL SUPPLY SYSTEMS AND COMPONENTS', [
      CurriculumBullet('Fundamental principles of alternating current'),
      CurriculumBullet(
          'Alternating current generation (distribution systems theory)'),
      CurriculumBullet(
          'Theories, concepts and principles of direct current sources'),
      CurriculumBullet(
          'Calculations of direct and alternating current circuits'),
      CurriculumBullet(
          'Construction and operating principles of direct current generators'),
    ]),
    CurriculumCategory('BATTERIES', [
      CurriculumBullet('Fundamentals of battery operation'),
      CurriculumBullet('Types and classification of batteries'),
      CurriculumBullet('Safety precautions of batteries'),
      CurriculumBullet('Care and maintenance of batteries'),
      CurriculumBullet('Battery components and construction'),
      CurriculumBullet('Disposal of batteries'),
    ]),
    CurriculumCategory('TRANSFORMERS', [
      CurriculumBullet(
          'Types of single phase transformers including single wound, double wound and auto-transformers and their applications'),
      CurriculumBullet('Transformer cooling systems'),
      CurriculumBullet('Principles of single phase transformer operation'),
      CurriculumBullet(
          'Formulas and calculations on input and output of transformers'),
      CurriculumBullet('Maintenance requirements of transformers'),
      CurriculumBullet('Types of three phase transformers and their applications'),
      CurriculumBullet(
          'Construction of three phase transformers including open core, closed core and shell or divided core'),
    ]),
    CurriculumCategory('TYPES OF CABLES AND APPLICATIONS', [
      CurriculumBullet(
          'Types of cable construction including armoured and un-armoured, insulated and un-insulated, single and multi core cables'),
      CurriculumBullet(
          'Cable materials and their functions and characteristics'),
      CurriculumBullet('Applications of various types of cable'),
      CurriculumBullet('Installation methods and safe use of cables'),
      CurriculumBullet('Safe transport and storage of cables'),
    ]),
    CurriculumCategory('LOW VOLTAGE PROTECTION', [
      CurriculumBullet('Purpose and application of low voltage protection'),
      CurriculumBullet('Types of low voltage protection'),
      CurriculumBullet(
          'Low voltage protection parameters and statutory requirements'),
    ]),
    CurriculumCategory('FAULT FINDING', [
      CurriculumBullet('Fault finding principles for electrical circuits'),
      CurriculumBullet('Fault finding techniques for electrical circuits'),
      CurriculumBullet('Safety during fault finding'),
    ]),
    CurriculumCategory(
        'INSTALLING WIRING AND CONNECTING ELECTRICAL EQUIPMENT', [
      CurriculumBullet('Conduct a preliminary risk assessment'),
      CurriculumBullet('Identify the hazards'),
      CurriculumBullet('Relate the risk to the hazard'),
      CurriculumBullet('Conduct mitigation of the risk'),
    ]),
    CurriculumCategory(
        'INSTALLING, WIRING AND CONNECTING ELECTRICAL EQUIPMENT AND CONTROL SYSTEMS',
        [
          CurriculumBullet('Determine functionality of tools and testing equipment'),
          CurriculumBullet('Load and off load resources'),
          CurriculumBullet('Procure type and size of moving equipment'),
          CurriculumBullet('Stack and secure tools, material and equipment'),
          CurriculumBullet('Store tools, material and equipment on site'),
          CurriculumBullet('Basic lifting techniques'),
          CurriculumBullet('Use of material safety data sheet'),
        ]),
    CurriculumCategory(
        'INSTALL, WIRE AND CONNECT ELECTRICAL EQUIPMENT AND CONTROL SYSTEMS',
        [
          CurriculumBullet('Inspection of site and installation'),
          CurriculumBullet('Risk assessment of the installation'),
          CurriculumBullet('Mitigate and or rectify the identified hazards'),
          CurriculumBullet(
              'Select equipment and control system according to design specifications'),
          CurriculumBullet('Interpret drawings'),
        ]),
    CurriculumCategory(
        'CONDUCT PRE-COMMISSION INSPECTION (POWER OFF) AND TEST', [
      CurriculumBullet(
          'Visually inspect installed equipment, control systems and installations'),
      CurriculumBullet('Confirm conductor and cable selection'),
      CurriculumBullet('Inspect all connections and terminations'),
    ]),
    CurriculumCategory('CARRYING OUT COMMISSIONING TESTS', [
      CurriculumBullet('Carry out risk assessment'),
      CurriculumBullet('Carry out relevant commissioning tests'),
      CurriculumBullet('Interpret commissioning tests results'),
      CurriculumBullet('Report commissioning results'),
      CurriculumBullet(
          'Isolate the defective electrical installation or control system'),
      CurriculumBullet(
          'Repair defects on electrical installation or control system'),
      CurriculumBullet(
          'Record and report commissioning test results of installations and control systems'),
    ]),
    CurriculumCategory(
        'FAULT FIND AND REPAIR ELECTRICAL CONTROL SYSTEMS AND ELECTRICAL INSTALLATIONS',
        [
          CurriculumBullet('Select hand and power tools'),
          CurriculumBullet('Select testing instruments'),
          CurriculumBullet(
              'Carry out tests that include but not limited to: visual inspections, functional, continuity, insulation resistance and polarity tests'),
          CurriculumBullet('Conduct fault finding'),
        ]),
  ],

  // ---------------------------------------------------------------------
  // BRICKLAYER — OFO 641201 (transcribed from the toolkit Appendix C
  // "Trade Curriculum Content Summary" pages, Trade Overview table)
  // ---------------------------------------------------------------------
  '641201': const [
    CurriculumCategory('SAFETY', [
      CurriculumBullet(
          'Occupational Health and Safety Act applicable to construction and how they impact or affect the work activities on a construction'),
      CurriculumBullet('Standard industrial safety'),
      CurriculumBullet('First aid course awareness'),
      CurriculumBullet(
          'Identify relevant colour and symbolic safety signs project/site'),
    ]),
    CurriculumCategory('KNOWLEDGE OF BASIC HAND TOOLS AND EQUIPMENT', [
      CurriculumBullet(
          'Interpret the importance of hand tools, power tools and equipment requirements for storage and handling'),
      CurriculumBullet(
          'Explain the importance of cleaning and maintenance of hand tools, power tools and equipment'),
      CurriculumBullet(
          'Identify measuring tools, Bricklaying tools, cutting tools, jointing tools, setting out tools, and common tools'),
    ]),
    CurriculumCategory('TYPES OF MATERIALS IN BRICKLAYING', [
      CurriculumBullet(
          'Properties, characteristics, functions and uses of different materials in building and construction'),
      CurriculumBullet(
          'Procedures for procurement of different materials, tools and equipment types'),
    ]),
    CurriculumCategory('UNDERSTANDING DRAWINGS AND SYMBOLS OF MATERIALS', [
      CurriculumBullet('Read and interpret drawings'),
      CurriculumBullet(
          'Interpret relevant symbols, abbreviations and colours'),
      CurriculumBullet(
          'Understand drawings which includes sectionals, isometric and orthographic projections in the first and third angle'),
      CurriculumBullet('Compile material lists from detail drawings'),
    ]),
    CurriculumCategory('ESTIMATION OF THE BUILDING MATERIAL', [
      CurriculumBullet(
          'Knowledge of different types of units of measurements of the different building materials'),
      CurriculumBullet(
          'Knowledge of material quantities per volume, area and length, and numbers'),
    ]),
    CurriculumCategory('SETTING OUT A BUILDING/DWELLING FROM A PLAN', [
      CurriculumBullet('Methods and techniques used for setting out'),
    ]),
    CurriculumCategory('EXCAVATE, CAST FOUNDATION AND CONCRETE FLOOR', [
      CurriculumBullet(
          'Set out building foundations and excavate foundation trenches'),
      CurriculumBullet(
          'Install levelling pegs, cast concrete foundations and build foundation walling'),
      CurriculumBullet('Backfill, compact and cast concrete slab'),
      CurriculumBullet(
          'Knowledge and understanding of different types of floors finishers'),
      CurriculumBullet(
          'Understanding of mix ratio for different types of floors'),
    ]),
    CurriculumCategory('DETERMINE AND TRANSFER LEVELS', [
      CurriculumBullet(
          'Describe and explain the different properties and use of tools and equipment for setting out and transfer of levels'),
      CurriculumBullet('Knowledge of different instruments'),
      CurriculumBullet(
          'Use of spirit level, dump level, laser level, plumb bob, water levelling and etc'),
    ]),
    CurriculumCategory('MIXING OF MORTAR', [
      CurriculumBullet(
          'Properties and use of products involved in mixing mortar and concrete'),
      CurriculumBullet(
          'Mortar mix is prepared in accordance with the required consistency'),
      CurriculumBullet(
          'Bonding agents are mixed according to required specification'),
      CurriculumBullet('Knowledge of different types of Sands and grading'),
      CurriculumBullet(
          "Knowledge of ratios as per manufacturers' specifications"),
      CurriculumBullet(
          'Water requirements for different types of mortar mixes'),
      CurriculumBullet('Preparation of the surface area for mixing Mortar'),
      CurriculumBullet(
          'Mixing of Mortar and understanding different ratio for different Mortar Mixes'),
      CurriculumBullet('Working with Mortar. Applying Mortar for different uses'),
    ]),
    CurriculumCategory('TYPES OF BRICK BONDS', [
      CurriculumBullet(
          'Foundation walling is built in accordance with drawing specifications and includes bond, brick, reinforcement'),
      CurriculumBullet(
          'Knowledge of Bonds Terms and reason/s for using different types of bonds in the Building Industry'),
    ]),
    CurriculumCategory('BUILD-IN OF: WINDOW FRAMES AND DOOR FRAMES', [
      CurriculumBullet(
          'Build superstructure in solid and cavity construction including the building in of door and window frames as well as precast lintels'),
      CurriculumBullet(
          'Knowledge and understanding of interpretation of building plans plus interpretation of specifications'),
      CurriculumBullet('Use of building profiles and straight edge'),
      CurriculumBullet(
          'Knowledge of types of bonds and other special bricks used for building face brick walls'),
    ]),
    CurriculumCategory('JOINTING AND POINTING OF BRICKWORK', [
      CurriculumBullet('Use of jointing tools and other finishing tools'),
      CurriculumBullet(
          'Conduct jointing, pointing and bagging activities'),
      CurriculumBullet('Understanding reasons for Jointing'),
      CurriculumBullet(
          'Knowledge of different types of joints and why they are used in brickwork'),
      CurriculumBullet(
          'Understanding the difference between jointing and Control Joints'),
      CurriculumBullet(
          'Understanding the reasons for using control joints in a Building'),
    ]),
    CurriculumCategory('REINFORCED CONCRETE CONSTRUCTION', [
      CurriculumBullet(
          'Lay reinforcement mesh where required and cast concrete slab'),
      CurriculumBullet(
          'Knowledge and use of different types of reinforcement'),
      CurriculumBullet('Knowledge of the different sizes of reinforcing bars'),
      CurriculumBullet(
          'Knowledge of and use of reinforcement bending schedules'),
      CurriculumBullet(
          'Knowledge of concrete ratios for different mixes and strength with regards to low strength, medium and high strength capacity requirements'),
    ]),
    CurriculumCategory('ARCH CONSTRUCTION', [
      CurriculumBullet('Lay precast and brick-on edge lintels and arches'),
      CurriculumBullet('Knowledge of constructing different arch templates'),
      CurriculumBullet(
          'Knowledge and understanding of decorative elements (Flat, semi-circular and segmented arches etc.)'),
    ]),
    CurriculumCategory('STEPS', [
      CurriculumBullet('Build brick steps'),
      CurriculumBullet('Knowledge of brick steps'),
      CurriculumBullet('Contains risers and threads etc'),
    ]),
  ],
};
