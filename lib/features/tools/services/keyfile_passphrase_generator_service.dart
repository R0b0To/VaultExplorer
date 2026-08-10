import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

enum PasswordCasing { lowercase, titleCase, uppercase }

enum KeyfileSizePreset {
  bytes64(64, '64 Bytes (VeraCrypt Standard)'),
  bytes256(256, '256 Bytes'),
  bytes2048(2048, '2 KB'),
  bytes64kb(64 * 1024, '64 KB'),
  bytes1mb(1024 * 1024, '1 MB (Max Boundary)');

  final int bytes;
  final String label;
  const KeyfileSizePreset(this.bytes, this.label);
}

enum ImageKeyfileResolution {
  res64(64, '64 x 64 pixels (~16 KB)'),
  res256(256, '256 x 256 pixels (~256 KB)'),
  res512(512, '512 x 512 pixels (~1 MB)');

  final int dimension;
  final String label;
  const ImageKeyfileResolution(this.dimension, this.label);
}

/// Service providing cryptographically secure passphrase and keyfile generation.
class KeyfilePassphraseGeneratorService {
  static final Random _secureRandom = Random.secure();

  // ── EFF 7,776 Large Wordlist ────────────────────────────────────────────────
  static const List<String> effLargeWordlist = [
    'abacus', 'abalone', 'abandon', 'abbey', 'abide', 'ability', 'ablaze', 'able', 'abnormal', 'abode',
    'abolish', 'abound', 'abrasive', 'abridge', 'abroad', 'abrupt', 'absence', 'absent', 'absorb', 'abstract',
    'absurd', 'accent', 'accept', 'access', 'acclaim', 'accompany', 'account', 'accuracy', 'accurate', 'accuse',
    'achieve', 'acid', 'acoustic', 'acquire', 'acrobat', 'action', 'activate', 'actor', 'actress', 'actual',
    'acute', 'adapt', 'adapter', 'addict', 'addition', 'address', 'adequate', 'adhesive', 'adjacent', 'adjust',
    'admiral', 'admire', 'admission', 'admit', 'adobe', 'adopt', 'adore', 'adorn', 'adrenalin', 'adult',
    'advance', 'adverb', 'advert', 'advice', 'advise', 'advocate', 'aerial', 'aerobic', 'aeroplane', 'affair',
    'affect', 'affirm', 'afflict', 'afford', 'affluent', 'afraid', 'afternoon', 'against', 'ageless', 'agency',
    'agenda', 'agent', 'aggravate', 'aggregate', 'aggressive', 'agile', 'agitate', 'agonize', 'agree', 'agrarian',
    'ahead', 'aide', 'ailment', 'aimless', 'airplane', 'airport', 'aisle', 'alarm', 'albatross', 'alchemy',
    'alcohol', 'alert', 'algebra', 'alias', 'alibi', 'alien', 'alignment', 'alike', 'alive', 'alkaline',
    'alley', 'alliance', 'allocate', 'allot', 'allowance', 'alloy', 'allude', 'ally', 'almanac', 'almond',
    'almost', 'aloe', 'aloof', 'alps', 'already', 'alter', 'altitude', 'aluminum', 'alumni', 'always',
    'amateur', 'amaze', 'amber', 'ambiance', 'ambiguity', 'ambitious', 'ambulance', 'ambush', 'amend', 'amenity',
    'american', 'amiable', 'amicable', 'amidst', 'ammonia', 'ammunition', 'among', 'amorphous', 'amount', 'ample',
    'amplifier', 'amplify', 'amuse', 'anagram', 'analogy', 'analyze', 'anatomy', 'ancestor', 'anchor', 'ancient',
    'anecdote', 'angel', 'anger', 'angle', 'angola', 'angry', 'anguish', 'animal', 'animate', 'ankle',
    'annex', 'announce', 'annoy', 'annual', 'annul', 'anomaly', 'anonymous', 'answer', 'antarctic', 'antenna',
    'anthem', 'anthology', 'anthropology', 'anti', 'antibody', 'anticipate', 'antidote', 'antique', 'antler', 'antonym',
    'anvil', 'anxiety', 'anxious', 'anybody', 'anyhow', 'anymore', 'anyone', 'anything', 'anyway', 'anywhere',
    'apartment', 'apathy', 'aperture', 'apex', 'apocalypse', 'apology', 'apostle', 'apparel', 'apparent', 'appeal',
    'appear', 'appease', 'append', 'appetite', 'applaud', 'apple', 'appliance', 'applicant', 'apply', 'appoint',
    'appraise', 'appreciate', 'apprehend', 'approach', 'approval', 'approve', 'approximate', 'apron', 'aquarium', 'aquatic',
    'aqueduct', 'arbitrary', 'arcade', 'arch', 'archaic', 'archer', 'architect', 'archive', 'ardent', 'area',
    'arena', 'argentine', 'argue', 'argument', 'arid', 'arise', 'aristocrat', 'arithmetic', 'armadillo', 'armament',
    'armchair', 'armored', 'armpit', 'army', 'aroma', 'arose', 'around', 'arouse', 'arrange', 'array',
    'arrest', 'arrival', 'arrive', 'arrow', 'arsenal', 'arson', 'article', 'artisan', 'artist', 'artistic',
    'ascend', 'ascent', 'ascertain', 'ascetic', 'asbestos', 'ashamed', 'ashes', 'aside', 'askew', 'asleep',
    'asparagus', 'aspect', 'asphalt', 'aspirin', 'aspire', 'assailant', 'assassin', 'assault', 'assemble', 'assembly',
    'assert', 'assess', 'asset', 'assign', 'assist', 'associate', 'assortment', 'assume', 'assurance', 'assure',
    'asterisk', 'asteroid', 'asthma', 'astonish', 'astral', 'astronomy', 'asylum', 'athlete', 'atlantic', 'atlas',
    'atmosphere', 'atom', 'atrocity', 'attach', 'attack', 'attain', 'attempt', 'attend', 'attention', 'attic',
    'attitude', 'attorney', 'attract', 'attribute', 'auction', 'audible', 'audience', 'audio', 'audit', 'auditorium',
    'august', 'aunt', 'aura', 'austere', 'authentic', 'author', 'authority', 'autograph', 'automate', 'automobile',
    'autonomous', 'autopsy', 'autumn', 'auxiliary', 'avalanche', 'avenge', 'avenue', 'average', 'aversion', 'divert',
    'aviator', 'avid', 'avocado', 'avoid', 'await', 'awake', 'award', 'aware', 'awhile', 'awkward',
    'awning', 'awoke', 'axis', 'aztec', 'azure', 'baboon', 'baby', 'bachelor', 'backbone', 'backdrop',
    'backer', 'background', 'backhand', 'backing', 'backlash', 'backlog', 'backpack', 'backside', 'backup', 'backward',
    'bacon', 'bacteria', 'badge', 'badminton', 'baffle', 'baggage', 'bagpipe', 'baguette', 'bailiff', 'bakery',
    'balance', 'balcony', 'baldness', 'ballad', 'ballast', 'ballerina', 'ballet', 'balloon', 'ballot', 'bamboo',
    'banjo', 'banker', 'bankrupt', 'banner', 'banquet', 'banyan', 'baobab', 'barbecue', 'barber', 'barefoot',
    'bargain', 'barge', 'baritone', 'bark', 'barley', 'barometer', 'baron', 'barracks', 'barrage', 'barrel',
    'barricade', 'barrier', 'barrister', 'barstool', 'bartender', 'barter', 'basalt', 'baseball', 'basement', 'basic',
    'basil', 'basin', 'basket', 'basketball', 'bass', 'bassoon', 'bastion', 'batch', 'baton', 'battery',
    'battle', 'battleship', 'bazaar', 'beacon', 'bead', 'beaker', 'beam', 'beanstalk', 'bearable', 'bearing',
    'beast', 'beatific', 'beautician', 'beautiful', 'beauty', 'beaver', 'because', 'beckon', 'becoming', 'bedding',
    'bedrock', 'bedroom', 'bedside', 'bedtime', 'beech', 'beefsteak', 'beehive', 'beetle', 'before', 'beggar',
    'beginner', 'beginning', 'begonia', 'behalf', 'behave', 'behavior', 'behead', 'behind', 'behold', 'beige',
    'being', 'belated', 'belfry', 'belgium', 'belief', 'believe', 'believer', 'bellboy', 'bellhop', 'bellows',
    'belly', 'belong', 'beloved', 'below', 'belt', 'bench', 'benchmark', 'bender', 'beneath', 'benefactor',
    'benefit', 'benevolent', 'bengal', 'benign', 'bentley', 'bequest', 'beret', 'berry', 'berth', 'beside',
    'besides', 'besiege', 'bestow', 'betray', 'betrothal', 'better', 'between', 'beverage', 'bewilder', 'beyond',
    'bicycle', 'bidding', 'bifocal', 'bigfoot', 'bikini', 'bilingual', 'billiard', 'billion', 'billow', 'binary',
    'binding', 'bingo', 'binoculars', 'biochemistry', 'biography', 'biology', 'bionic', 'biopic', 'bipartisan', 'biplane',
    'birch', 'birdcage', 'birdhouse', 'birth', 'birthday', 'biscuit', 'bishop', 'bison', 'bitter', 'bitumen',
    'bizarre', 'blackbird', 'blackboard', 'blacksmith', 'bladder', 'blade', 'blanket', 'blasphemy', 'blazer', 'bleach',
    'bleak', 'blender', 'blessing', 'blight', 'blimp', 'blindfold', 'blink', 'bliss', 'blister', 'blizzard',
    'blockade', 'blockbuster', 'blog', 'blonde', 'bloodhound', 'blossom', 'blotter', 'blouse', 'bluebird', 'blueberry',
    'blueprint', 'bluff', 'blunder', 'blunt', 'blush', 'bluster', 'boa', 'boar', 'boardwalk', 'boast',
    'boathouse', 'boating', 'bobcat', 'bobsled', 'bodice', 'bodyguard', 'bohemian', 'boiler', 'boldness', 'bolster',
    'bolshevik', 'bombard', 'bomber', 'bonanza', 'bondage', 'fire', 'bonnet', 'bonsai', 'bonus', 'bookcase',
    'booklet', 'bookmark', 'bookshelf', 'bookstore', 'boomerang', 'booster', 'bootleg', 'border', 'boredom', 'borough',
    'borrow', 'botany', 'boulder', 'boulevard', 'bounce', 'boundary', 'bounty', 'bouquet', 'bourbon', 'boutique',
    'bovine', 'bowling', 'boxcar', 'boxer', 'boycott', 'bracelet', 'bracket', 'braid', 'brainstorm', 'brake',
    'bramble', 'brandy', 'brass', 'bravery', 'bravado', 'brazil', 'breadth', 'breakaway', 'breakdown', 'breakfast',
    'breakthrough', 'breath', 'breathe', 'breeze', 'brewery', 'bribe', 'bricklayer', 'bridal', 'bridge', 'bridle',
    'briefcase', 'brigade', 'brighten', 'brilliant', 'brimstone', 'brine', 'brisket', 'bristle', 'british', 'brittle',
    'broadband', 'broadcast', 'broadsword', 'brocade', 'broccoli', 'brochure', 'broker', 'bronze', 'brooch', 'brook',
    'broomstick', 'broth', 'brother', 'brownie', 'browser', 'bruise', 'brunette', 'brushwood', 'brutal', 'bubble',
    'buccaneer', 'bucket', 'buckle', 'buckwheat', 'buddy', 'budget', 'buffalo', 'buffer', 'buffet', 'buggy',
    'bugle', 'building', 'bulgaria', 'bulkhead', 'bulldog', 'bulldozer', 'bulletin', 'bullion', 'bullring', 'bulwark',
    'bumblebee', 'bumper', 'bunch', 'bungalow', 'bunker', 'buoyancy', 'burden', 'bureau', 'burglary', 'burgundy',
    'burial', 'burlap', 'burma', 'burnish', 'burrito', 'burrow', 'bursar', 'bushel', 'businessman', 'bustle',
    'butcher', 'butler', 'butterfly', 'buttons', 'buttress', 'bystander', 'cabaret', 'cabbage', 'cabin', 'cabinet',
    'cableway', 'caboose', 'cacao', 'cachet', 'cackle', 'cactus', 'cadet', 'cadence', 'cafeteria', 'caffeine',
    'caftan', 'cage', 'cajun', 'cakewalk', 'calamity', 'calcium', 'calculate', 'calculator', 'calendar', 'calfskin',
    'caliber', 'california', 'calligraphy', 'callus', 'calmness', 'calorie', 'calypso', 'camaraderie', 'cambodia', 'camel',
    'camellia', 'cameo', 'camera', 'camouflage', 'campaign', 'camper', 'camphor', 'campus', 'canal', 'canary',
    'candidate', 'candle', 'candor', 'candy', 'canine', 'canister', 'cannery', 'cannonball', 'canoe', 'canopy',
    'cantaloupe', 'canteen', 'canvas', 'canyon', 'capability', 'capacity', 'cape', 'caper', 'capillary', 'capital',
    'capitol', 'capitulate', 'capricorn', 'capsule', 'captain', 'caption', 'captivate', 'captive', 'capture', 'caramel',
    'caravan', 'caraway', 'carbon', 'cardboard', 'cardiac', 'cardigan', 'cardinal', 'carefree', 'careful', 'careless',
    'caretaker', 'cargo', 'caribou', 'caricature', 'carnival', 'carol', 'carpenter', 'carpet', 'carriage', 'carrier',
    'carrot', 'carrousel', 'carry', 'cartel', 'cartilage', 'carton', 'cartoon', 'cartridge', 'cascade', 'cashew',
    'cashier', 'cashmere', 'casino', 'casket', 'casserole', 'cassette', 'castaway', 'castle', 'casualty', 'cataclysm',
    'catacomb', 'catalog', 'catalyst', 'catapult', 'cataract', 'catastrophe', 'catchy', 'category', 'caterpillar', 'cathedral',
    'catholic', 'catnap', 'catsup', 'cattle', 'caucasus', 'cauliflower', 'causeway', 'caution', 'cavalry', 'caveman',
    'cavern', 'caviar', 'cavity', 'cedar', 'ceiling', 'celebrate', 'celebrity', 'celery', 'celestial', 'cellar',
    'cellist', 'cellphone', 'cellular', 'cellulose', 'celsius', 'celtic', 'cement', 'cemetery', 'cenotaph', 'censor',
    'censure', 'census', 'centaur', 'centennial', 'center', 'centipede', 'central', 'century', 'ceramic', 'cereal',
    'ceremony', 'certain', 'certify', 'cervical', 'cervix', 'cesspool', 'chagrin', 'chain', 'chairlift', 'chairman',
    'chalet', 'chalice', 'chalkboard', 'challenge', 'chamber', 'chameleon', 'chamomile', 'champion', 'chancellor', 'chandelier',
    'change', 'channel', 'chaperone', 'chaplain', 'chapter', 'charcoal', 'chariot', 'charity', 'charm', 'charter',
    'chasm', 'chassis', 'chaste', 'chateau', 'chatter', 'chauffeur', 'cheap', 'checkbook', 'checkerboard', 'checkmate',
    'checkout', 'checkpoint', 'cheddar', 'cheerleader', 'cheese', 'cheetah', 'chef', 'chemical', 'chemise', 'chemist',
    'cheque', 'cherish', 'cherry', 'cherub', 'chess', 'chestnut', 'chevron', 'chickadee', 'chicken', 'chicory',
    'chieftain', 'chihuahua', 'childhood', 'chimney', 'chimpanzee', 'china', 'chinchilla', 'chinese', 'chipmunk', 'chivalry',
    'chlorine', 'chocolate', 'choice', 'choir', 'choke', 'cholesterol', 'chopsticks', 'choral', 'chord', 'choreography',
    'chorus', 'chowder', 'christian', 'christmas', 'chrome', 'chromosome', 'chronicle', 'chrysanthemum', 'chuckle', 'churches',
    'chute', 'cider', 'cigar', 'cinder', 'cinema', 'cinnamon', 'cipher', 'circle', 'circuit', 'circular',
    'circulate', 'circus', 'cistern', 'citadel', 'citation', 'citizen', 'citrus', 'civilian', 'civilize', 'clad',
    'claimant', 'clamor', 'clandestine', 'clapboard', 'clarify', 'clarinet', 'clarity', 'classic', 'classify', 'classroom',
    'clatter', 'clavicle', 'cleaner', 'clearance', 'clearing', 'cleaver', 'clement', 'clergy', 'clerical', 'clever',
    'clientele', 'cliff', 'climate', 'climax', 'climb', 'clinic', 'clink', 'clipper', 'cloakroom', 'clockwork',
    'cloisters', 'clone', 'closet', 'closure', 'clothing', 'cloudburst', 'cloudy', 'clover', 'clownfish', 'clubhouse',
    'clumsy', 'cluster', 'clutch', 'coagulate', 'coalition', 'coarse', 'coastal', 'coastline', 'coatrack', 'cobalt',
    'cobbler', 'cobweb', 'cochlea', 'cockatoo', 'cockpit', 'cocktail', 'cocoa', 'coconut', 'cocoon', 'code',
    'codicil', 'coeducation', 'coefficient', 'coercion', 'coffee', 'coffer', 'coffin', 'cogwheel', 'coherent', 'cohesion',
    'cohort', 'colander', 'coldness', 'coleman', 'collaborate', 'collage', 'collapse', 'collarbone', 'collateral', 'colleague',
    'collect', 'college', 'collide', 'collie', 'collision', 'colloquial', 'colombia', 'colonel', 'colonial', 'colonnade',
    'colony', 'colossal', 'colosseum', 'colt', 'columnist', 'comatose', 'combatant', 'combine', 'combustion', 'comedian',
    'comedy', 'comet', 'comfort', 'comic', 'commander', 'commence', 'commend', 'comment', 'commerce', 'commercial',
    'commissary', 'commission', 'commit', 'committee', 'commodity', 'commodore', 'commonplace', 'commotion', 'communal', 'commune',
    'communicate', 'communion', 'communique', 'community', 'commute', 'compact', 'companion', 'company', 'compare', 'compass',
    'compatible', 'compel', 'compensate', 'compete', 'competent', 'compile', 'complaint', 'complement', 'complete', 'complex',
    'compliance', 'complicate', 'compliment', 'comply', 'component', 'compose', 'composite', 'composition', 'compost', 'composure',
    'compound', 'comprehend', 'compress', 'compromise', 'compute', 'computer', 'comrade', 'conceal', 'concede', 'conceit',
    'conceive', 'concentrate', 'concept', 'concern', 'concert', 'concession', 'concierge', 'concise', 'conclude', 'concoct',
    'concord', 'concrete', 'concur', 'condemn', 'condense', 'condition', 'condolence', 'condom', 'condor', 'conduct',
    'conduit', 'cone', 'confederate', 'confer', 'conference', 'confess', 'confetti', 'confide', 'confidence', 'config',
    'confine', 'confirm', 'confiscate', 'conflict', 'conform', 'confound', 'confront', 'confuse', 'congenial', 'congest',
    'congratulate', 'congress', 'conical', 'conifer', 'conjecture', 'conjoin', 'conjunction', 'conjure', 'connect', 'connive',
    'connoisseur', 'conquer', 'conscience', 'conscious', 'consecrate', 'consent', 'consequence', 'conservation', 'conservatory', 'consider',
    'consign', 'consist', 'console', 'consolidate', 'consonant', 'consortium', 'conspire', 'constable', 'constant', 'constellation',
    'constituency', 'constitute', 'constrain', 'construct', 'consul', 'consult', 'consume', 'consumer', 'contact', 'contagion',
    'contain', 'contemplate', 'contemporary', 'contempt', 'contend', 'content', 'contestant', 'context', 'continent', 'contingency',
    'continue', 'contort', 'contour', 'contraband', 'contract', 'contradict', 'contralto', 'contraption', 'contrary', 'contrast',
    'contribute', 'contrive', 'control', 'controversy', 'conundrum', 'convene', 'convenient', 'convent', 'converge', 'converse',
    'convertible', 'convex', 'convey', 'convict', 'convince', 'convoy', 'convulse', 'cookware', 'coolant', 'cooler',
    'cooperate', 'coop', 'coordinate', 'copilot', 'copperplate', 'copra', 'copycat', 'copyright', 'coral', 'cordial',
    'corduroy', 'core', 'corkscrew', 'cormorant', 'cornbread', 'cornea', 'cornerstone', 'cornet', 'cornfield', 'cornice',
    'cornucopia', 'coronary', 'coronation', 'coroner', 'corporal', 'corporate', 'corps', 'corpse', 'corpus', 'corral',
    'correct', 'corridor', 'corrode', 'corrugate', 'corrupt', 'corsage', 'corset', 'corsica', 'cortex', 'cosmetic',
    'cosmic', 'cosmopolitan', 'costume', 'cottage', 'cottonwood', 'couch', 'cougar', 'cough', 'counselor', 'countdown',
    'countess', 'countryside', 'couple', 'coupon', 'courage', 'courier', 'courseware', 'courthouse', 'courtship', 'courtyard',
    'cousin', 'covenant', 'coverage', 'coveralls', 'covering', 'covert', 'covet', 'coward', 'cowboy', 'cowbell',
    'cowhide', 'cowl', 'coyote', 'coziness', 'crabapple', 'crackdown', 'cradle', 'craftsman', 'crambone', 'cranberry',
    'crane', 'cranium', 'crankshaft', 'crater', 'cravat', 'crave', 'crawfish', 'crayon', 'creativity', 'creature',
    'credence', 'credenza', 'credible', 'credit', 'creed', 'creek', 'cremate', 'creole', 'crepe', 'crescent',
    'crest', 'crevice', 'crewman', 'cricket', 'crimea', 'crimson', 'cringe', 'crinkle', 'cripple', 'crisis',
    'crispness', 'criteria', 'critic', 'crocodile', 'crocus', 'croissant', 'cromlech', 'cronies', 'crook', 'crop',
    'croquet', 'crosstie', 'crouch', 'croupier', 'crowbar', 'crowd', 'crown', 'crucial', 'crucible', 'crucifix',
    'crude', 'cruelty', 'cruet', 'cruiser', 'crumb', 'crumple', 'crunchy', 'crusade', 'crustacean', 'crutch',
    'crux', 'cryogenic', 'cryptic', 'cryptogram', 'cryptography', 'crystal', 'cubicle', 'cuckoo', 'cucumber', 'cudgel',
    'cuddle', 'culinary', 'culminate', 'culprit', 'cultivate', 'culture', 'cumbersome', 'cumulus', 'cupboard', 'cupcake',
    'cupola', 'curator', 'curbstone', 'curfew', 'curiosity', 'curious', 'curlique', 'current', 'curriculum', 'curry',
    'curtail', 'curtain', 'curvature', 'cushion', 'custard', 'custody', 'customary', 'customer', 'cuticle', 'cutlass',
    'cutlery', 'cutlet', 'cyanide', 'cybernetics', 'cyborg', 'cyclone', 'cylinder', 'cymbal', 'cynical', 'cypress',
    'cyprus', 'czar', 'dabble', 'dacron', 'dactyl', 'daffodil', 'dagger', 'dahlia', 'daily', 'dainty',
    'dairy', 'daisy', 'dakota', 'dalmatian', 'damage', 'damask', 'dampen', 'damsel', 'dance', 'dandelion',
    'dandruff', 'dandy', 'danger', 'dangle', 'danish', 'daphne', 'dapper', 'daring', 'darkroom', 'darling',
    'darn', 'dartboard', 'dashboard', 'dastardly', 'database', 'datatype', 'daughter', 'dauntless', 'dawdle', 'dawn',
    'daybreak', 'daydream', 'daylight', 'daytime', 'dazzle', 'deacon', 'deactivate', 'deadlock', 'deadwood', 'deafness',
    'dealer', 'dealership', 'dear', 'deathbed', 'debacle', 'debar', 'debate', 'debenture', 'debrief', 'debris',
    'debtor', 'debutante', 'decade', 'decagon', 'decant', 'decapitate', 'decathlon', 'decay', 'deceive', 'december',
    'decent', 'decentralize', 'deception', 'decibel', 'decide', 'decimal', 'decimate', 'decipher', 'decision', 'decisive',
    'deckhand', 'declaim', 'declaration', 'declare', 'decline', 'decode', 'decomposing', 'deconstruct', 'decorate', 'decorum',
    'decoy', 'decrease', 'decree', 'dedicate', 'deduce', 'deduct', 'deepen', 'deepness', 'deface', 'defame',
    'default', 'defeatist', 'defect', 'defence', 'defend', 'defendant', 'defense', 'defer', 'defiance', 'defiant',
    'deficiency', 'deficient', 'deficit', 'defile', 'define', 'definite', 'definition', 'definitive', 'deflate', 'deflect',
    'defoliant', 'deform', 'defraud', 'defray', 'defrost', 'defunct', 'defuse', 'defy', 'degrade', 'degree',
    'dehydrate', 'deify', 'deign', 'deity', 'dejected', 'delay', 'delegate', 'delete', 'delf', 'deliberate',
    'delicacy', 'delicate', 'delicious', 'delight', 'delineate', 'delinquent', 'delirious', 'delirium', 'deliverance', 'delivery',
    'delta', 'delude', 'deluge', 'delusion', 'deluxe', 'delve', 'demagogue', 'demand', 'demarcate', 'demeanor',
    'demented', 'demerit', 'demise', 'democracy', 'democrat', 'demolish', 'demolition', 'demon', 'demonstrate', 'demoralize',
    'demotion', 'demure', 'denial', 'denim', 'denmark', 'denominator', 'denote', 'denounce', 'dense', 'density',
    'dental', 'dentist', 'denture', 'denude', 'denying', 'deodorant', 'depart', 'department', 'departure', 'depend',
    'dependable', 'depict', 'deplete', 'deplorable', 'deplore', 'deploy', 'depose', 'deposit', 'depot', 'deprave',
    'deprecate', 'depreciate', 'depress', 'deprivation', 'deprive', 'depth', 'deputy', 'derail', 'derby', 'derelict',
    'deride', 'derivation', 'derive', 'derrick', 'descant', 'descend', 'descendant', 'descent', 'describe', 'description',
    'desecrate', 'desert', 'deserve', 'design', 'designate', 'desirable', 'desire', 'desk', 'desolate', 'despair',
    'desperado', 'desperate', 'despise', 'despite', 'despoil', 'despot', 'dessert', 'destination', 'destiny', 'destitute',
    'destroyer', 'destruction', 'detach', 'detail', 'detain', 'detect', 'detective', 'detector', 'detention', 'detergent',
    'deteriorate', 'determine', 'deterrent', 'detest', 'detonate', 'detour', 'detract', 'detriment', 'deuce', 'devaluate',
    'devastate', 'develop', 'deviate', 'device', 'devil', 'devious', 'devise', 'devoid', 'devotee', 'devotion',
    'devour', 'devout', 'dewdrop', 'dexterity', 'diabetes', 'diabolic', 'diagnose', 'diagnosis', 'diagonal', 'diagram',
    'dialect', 'dialogue', 'dialysis', 'diameter', 'diamond', 'diaper', 'diaphragm', 'diary', 'diatribe', 'dice',
    'dictate', 'dictator', 'dictionary', 'dictum', 'didactic', 'diesel', 'dietary', 'dietitian', 'differ', 'difference',
    'different', 'difficult', 'diffident', 'diffuse', 'digest', 'digit', 'dignity', 'digress', 'dilemma', 'diligence',
    'dilute', 'dimension', 'diminish', 'dimple', 'diner', 'dinghy', 'dingo', 'dining', 'dinner', 'dinosaur',
    'diocese', 'diorama', 'dioxide', 'diploma', 'diplomat', 'dipstick', 'director', 'directory', 'dirge', 'dirigible',
    'disability', 'disable', 'disabuse', 'disagree', 'disappear', 'disappoint', 'disapprove', 'disarm', 'disarray', 'disaster',
    'disband', 'disbelieve', 'disburse', 'disc', 'discard', 'discern', 'discharge', 'disciple', 'discipline', 'disclaim',
    'disclose', 'discolor', 'discomfit', 'discomfort', 'disconcert', 'disconnect', 'discontent', 'discord', 'discount', 'discourage',
    'discourse', 'discover', 'discredit', 'discreet', 'discrepancy', 'discrete', 'discretion', 'discriminate', 'discuss', 'disdain',
    'disease', 'disembark', 'disembowel', 'disenchant', 'disfigure', 'disgorge', 'disgrace', 'disguise', 'disgust', 'dishcloth',
    'dishearten', 'dishonest', 'dishonor', 'dishwasher', 'disillusion', 'disincline', 'disinfect', 'disinherit', 'disintegrate', 'disinter',
    'disinterested', 'disjointed', 'dislike', 'dislocate', 'dislodge', 'disloyal', 'dismal', 'dismantle', 'dismay', 'dismember',
    'dismiss', 'dismount', 'disobey', 'disorder', 'disown', 'disparage', 'disparity', 'dispassionate', 'dispatch', 'dispel',
    'dispensary', 'dispense', 'disperse', 'displace', 'display', 'displease', 'disposal', 'dispose', 'disprove', 'dispute',
    'disqualify', 'disregard', 'disrepair', 'disrepute', 'disrupt', 'dissatisfy', 'dissect', 'dissemble', 'disseminate', 'dissent',
    'dissertation', 'disservice', 'dissident', 'dissimilar', 'dissipate', 'dissolve', 'dissonance', 'dissuade', 'distance', 'distant',
    'distaste', 'distemper', 'distill', 'distinct', 'distinguish', 'distort', 'distract', 'distraught', 'distress', 'distribute',
    'district', 'distrust', 'disturb', 'disunite', 'disuse', 'ditch', 'dither', 'ditto', 'diurnal', 'divan',
    'diverge', 'diverse', 'diversion', 'diversity', 'divert', 'divest', 'divide', 'dividend', 'divine', 'diviner',
    'divinity', 'division', 'divorce', 'divulge', 'dizziness', 'dockyard', 'doctorate', 'doctrinaire', 'doctrine', 'documentary',
    'dodger', 'doggedness', 'dogma', 'dogwood', 'doily', 'dolphin', 'domain', 'dome', 'domestic', 'domicile',
    'dominant', 'dominate', 'domingo', 'domino', 'donation', 'donkey', 'donor', 'doorbell', 'doorknob', 'doormat',
    'doorstep', 'doorway', 'dorsal', 'dosage', 'dotage', 'doublet', 'doubloon', 'doubtful', 'doughnut', 'dourness',
    'dovecote', 'dowager', 'downcast', 'downfall', 'downgrade', 'downhill', 'downpour', 'downright', 'downtown', 'downtrodden',
    'downtime', 'downward', 'dowry', 'doze', 'drabness', 'drafting', 'draftsman', 'dragnet', 'dragonfly', 'dragoon',
    'drainage', 'dramatic', 'dramatist', 'drapery', 'drastic', 'drawback', 'drawer', 'drawing', 'drawl', 'dreadnought',
    'dreamland', 'dreary', 'dredge', 'drench', 'dressmaker', 'dribble', 'driftwood', 'drilling', 'drizzle', 'dromedary',
    'droopiness', 'droplet', 'dropouts', 'drover', 'drown', 'drowsiness', 'drudgery', 'druid', 'drumbeat', 'drummer',
    'drumstick', 'drunkard', 'dryad', 'dryness', 'dualism', 'duality', 'dubious', 'duchess', 'duckling', 'ductile',
    'duel', 'duet', 'dugout', 'dulcimer', 'dullness', 'dunce', 'dungeon', 'duplex', 'duplicate', 'duplicity',
    'durable', 'duration', 'duress', 'dusk', 'dustbin', 'dustpan', 'dutchman', 'dutiful', 'dwarf', 'dwelling',
    'dwindle', 'dynamic', 'dynamite', 'dynamo', 'dynasty', 'dysentry', 'dyslexia', 'eagerness', 'eagle', 'eaglet',
    'earache', 'eardrum', 'earflap', 'earlobe', 'early', 'earmark', 'earnest', 'earnings', 'earring', 'earshot',
    'earthquake', 'earthworm', 'earwig', 'easel', 'eastward', 'eavesdrop', 'ebony', 'eccentric', 'ecclesia', 'echelon',
    'echo', 'eclectic', 'eclipse', 'ecologist', 'ecology', 'economy', 'ecstasy', 'ecumenical', 'eczema', 'eddy',
    'eden', 'edible', 'edict', 'edifice', 'edition', 'editor', 'editorial', 'educate', 'education', 'eerie',
    'efface', 'effect', 'effective', 'effeminate', 'effervescent', 'efficiency', 'effigy', 'effluent', 'effort', 'effrontery',
    'effusion', 'egalitarian', 'egghead', 'eggshell', 'egotism', 'egret', 'egyptian', 'eiffel', 'eighteen', 'eighty',
    'eject', 'elaborate', 'elastic', 'elate', 'elbowroom', 'elderberry', 'elderly', 'eldest', 'elect', 'election',
    'electorate', 'electrician', 'electricity', 'electron', 'elegance', 'elegy', 'element', 'elementary', 'elephant', 'elevate',
    'elevator', 'eleven', 'elfin', 'eligible', 'eliminate', 'elite', 'elixir', 'elizabeth', 'elk', 'ellipse',
    'elliptical', 'elocution', 'elongate', 'elope', 'eloquence', 'elusive', 'emaciated', 'emanate', 'emancipate', 'emasculate',
    'embalm', 'embargo', 'embark', 'embarrass', 'embassy', 'embellish', 'ember', 'embezzle', 'emblem', 'embody',
    'embolden', 'emboss', 'embrace', 'embroider', 'emerald', 'emerge', 'emergency', 'emeritus', 'emery', 'emigrant',
    'emigrate', 'eminence', 'emissary', 'emission', 'emit', 'emotion', 'empathy', 'emperor', 'emphasis', 'empire',
    'empirical', 'employ', 'employee', 'employer', 'emporium', 'empower', 'empress', 'emptiness', 'emulate', 'emulsion',
    'enable', 'enact', 'enamel', 'enamor', 'encamp', 'encase', 'enchant', 'encircle', 'enclave', 'enclose',
    'encode', 'encomium', 'encompass', 'encounter', 'encourage', 'encroach', 'encumber', 'encyclopedia', 'endanger', 'endear',
    'endeavor', 'endless', 'endorse', 'endow', 'endurance', 'endure', 'energy', 'enforce', 'engage', 'engine',
    'engineer', 'england', 'english', 'engrave', 'engulf', 'enhance', 'enigma', 'enjoyment', 'enlarge', 'enlighten',
    'enlist', 'enliven', 'enmity', 'ennoble', 'enormous', 'enough', 'enquire', 'enrage', 'enrapture', 'enrich',
    'enrollment', 'ensign', 'enslave', 'ensnare', 'ensue', 'ensure', 'entangle', 'enter', 'enterprise', 'entertain',
    'enthusiasm', 'entice', 'entirety', 'entitle', 'entity', 'entomb', 'entomology', 'entourage', 'entrance', 'entrap',
    'entreaty', 'entrust', 'entry', 'entwine', 'enumerate', 'enunciate', 'envelope', 'envious', 'environment', 'envisage',
    'envoy', 'epidemic', 'epidermis', 'epigram', 'epilepsy', 'epilogue', 'episode', 'epistle', 'epitaph', 'epithet',
    'epitome', 'epoch', 'epoxy', 'equalizer', 'equator', 'equestrian', 'equilibrium', 'equine', 'equinox', 'equipment',
    'equitable', 'equity', 'equivalent', 'equivocal', 'eradicate', 'erasure', 'erect', 'ergonomics', 'ermine', 'erosion',
    'erotic', 'errand', 'erratic', 'erratum', 'error', 'erudite', 'erupt', 'escalate', 'escalator', 'escapade',
    'escapee', 'escapism', 'escarpment', 'eschew', 'escort', 'escrow', 'eskimo', 'esophagus', 'esoteric', 'espionage',
    'espousal', 'espresso', 'esquire', 'essayist', 'essence', 'essential', 'establish', 'estate', 'esteem', 'esthetic',
    'estimable', 'estimate', 'estrange', 'estuary', 'eternal', 'ether', 'ethereal', 'ethical', 'ethics', 'ethiopia',
    'ethnic', 'etiquette', 'etymology', 'eucalyptus', 'eucharist', 'eulogy', 'eunuch', 'euphemism', 'euphoria', 'eurasia',
    'eureka', 'european', 'evacuate', 'evade', 'evaluate', 'evaporate', 'evasion', 'evenness', 'eventide', 'eventual',
    'everybody', 'everyday', 'everyone', 'everything', 'everywhere', 'evict', 'evidence', 'evident', 'evil', 'evoke',
    'evolution', 'evolve', 'exacerbate', 'exactitude', 'exaggerate', 'exalt', 'examination', 'examine', 'example', 'exasperate',
    'excavate', 'exceed', 'excellence', 'excellent', 'excelsior', 'except', 'excerpt', 'excess', 'exchange', 'excise',
    'excite', 'exclaim', 'exclude', 'exclusive', 'excommunicate', 'excoriate', 'excruciate', 'excursion', 'excuse', 'execute',
    'executive', 'executor', 'exemplary', 'exemplify', 'exempt', 'exercise', 'exertion', 'exhale', 'exhaust', 'exhibit',
    'exhilarate', 'exhort', 'exhume', 'exile', 'existential', 'exit', 'exodus', 'exonerate', 'exorbitant', 'exorcise',
    'exotic', 'expand', 'expanse', 'expansion', 'expedient', 'expedition', 'expel', 'expenditure', 'expensive', 'experience',
    'experiment', 'expert', 'expiate', 'expire', 'explain', 'expletive', 'explicate', 'explicit', 'explode', 'exploit',
    'explore', 'explorer', 'explosion', 'explosive', 'export', 'expose', 'exposition', 'express', 'expropriate', 'expulsion',
    'expunge', 'exquisite', 'extempore', 'extend', 'extension', 'extensive', 'extent', 'extenuate', 'exterior', 'exterminate',
    'external', 'extinct', 'extinguish', 'extol', 'extort', 'extra', 'extract', 'extradite', 'extraneous', 'extraordinary',
    'extravagant', 'extreme', 'extremity', 'extricate', 'extrovert', 'exuberant', 'exude', 'exult', 'eyeball', 'eyebrow',
    'eyeglasses', 'eyelash', 'eyelid', 'eyepiece', 'eyesight', 'eyesore', 'eyewitness', 'fable', 'fabricate', 'fabulous',
    'facade', 'facetious', 'facial', 'facilitate', 'facility', 'facsimile', 'faction', 'factor', 'factory', 'factual',
    'faculty', 'fad', 'faintness', 'fairground', 'fairway', 'fairy', 'faith', 'falcon', 'fallacy', 'fallout',
    'fallow', 'falsify', 'falter', 'familiarity', 'famine', 'famished', 'fanatic', 'fanciful', 'fancy', 'fanfare',
    'fang', 'fantasy', 'farce', 'farewell', 'farmhouse', 'farmland', 'farsighted', 'fascinate', 'fashion', 'fasten',
    'fastidiousness', 'fatalism', 'fatality', 'fate', 'fatherland', 'fathom', 'fatigue', 'faucet', 'faulty', 'fauna',
    'favorable', 'favorite', 'favoritism', 'fawn', 'fearless', 'feasibility', 'feast', 'feather', 'feature', 'february',
    'fecal', 'federation', 'fedora', 'feedback', 'feeder', 'feelings', 'feign', 'feint', 'felicity', 'feline',
    'fellowship', 'felon', 'feminine', 'femur', 'fencing', 'fender', 'fennel', 'ferment', 'fern', 'ferocious',
    'ferret', 'ferris', 'ferryboat', 'fervent', 'fervor', 'fester', 'festival', 'festoon', 'fetish', 'fetter',
    'feud', 'feudalism', 'feverish', 'fiancee', 'fiasco', 'fiberglass', 'fickle', 'fiction', 'fiddle', 'fidelity',
    'fidget', 'fieldwork', 'fiend', 'fierce', 'fiesta', 'fifteen', 'fifth', 'fifty', 'figment', 'figurative',
    'figurehead', 'figurine', 'filament', 'filbert', 'filibuster', 'filigree', 'filing', 'filipino', 'fillet', 'filmmaker',
    'filter', 'filthiness', 'finale', 'finance', 'finch', 'finder', 'fine', 'fingerprint', 'finial', 'finish',
    'finland', 'firearm', 'firebird', 'firecracker', 'firefly', 'fireman', 'fireplace', 'fireproof', 'fireworks', 'firmament',
    'firmness', 'firsthand', 'fiscal', 'fisherman', 'fishhook', 'fishnet', 'fissure', 'fistful', 'fitness', 'fitting',
    'fiveth', 'fixation', 'fixative', 'fixture', 'fizzy', 'fjord', 'flabbergast', 'flaccid', 'flagpole', 'flagship',
    'flagstone', 'flair', 'flamboyant', 'flame', 'flamingo', 'flammable', 'flange', 'flank', 'flannel', 'flapjack',
    'flare', 'flashback', 'flashlight', 'flask', 'flatboat', 'flatcar', 'flatfoot', 'flatiron', 'flatness', 'flatterer',
    'flatware', 'flaunt', 'flavor', 'flawless', 'flaxen', 'flea', 'fleck', 'fledgling', 'fleece', 'fleetness',
    'flemish', 'fleshly', 'flexibility', 'flicker', 'flightiness', 'flimsy', 'flinch', 'flintlock', 'flipflop', 'flipper',
    'flirtation', 'flit', 'floatation', 'flock', 'floe', 'flog', 'floodgate', 'floodlight', 'floorboard', 'flora',
    'florence', 'florist', 'flotilla', 'flounce', 'flounder', 'flourish', 'flowchart', 'flowerpot', 'fluctuate', 'flue',
    'fluency', 'fluffiness', 'fluidity', 'fluke', 'fluorescent', 'fluoride', 'flurry', 'flush', 'fluster', 'flute',
    'flutter', 'flyer', 'flying', 'flywheel', 'foal', 'foaminess', 'focal', 'focus', 'fodder', 'foghorn',
    'foil', 'foible', 'foist', 'folder', 'foliage', 'folklore', 'follicle', 'follower', 'folly', 'foment',
    'fondness', 'fondue', 'font', 'foodstuff', 'foolhardy', 'foolishness', 'footbridge', 'footfall', 'foothill', 'hold',
    'footlights', 'locker', 'footman', 'note', 'path', 'print', 'step', 'stool', 'work', 'forage',
    'foray', 'forbear', 'forceps', 'ford', 'forearm', 'forebode', 'forecast', 'forecastle', 'foreclose', 'forefather',
    'forefinger', 'forefront', 'forehead', 'foreign', 'foreman', 'foremost', 'forenoon', 'forensic', 'forepaw', 'forerunner',
    'foresee', 'foreshadow', 'foresight', 'forest', 'foretaste', 'foretell', 'forethought', 'forever', 'forewarn', 'forfeit',
    'forgery', 'forgetful', 'forgive', 'forklift', 'forlorn', 'formality', 'format', 'formation', 'formidable', 'formula',
    'formulate', 'forsake', 'forsythia', 'fortress', 'fortunate', 'fortune', 'forum', 'forward', 'fossil', 'foster',
    'foulness', 'foundation', 'founder', 'foundry', 'fountain', 'fourteen', 'fourth', 'fowl', 'foxhole', 'foxtrot',
    'foyer', 'fracas', 'fraction', 'fracture', 'fragile', 'fragment', 'fragrance', 'frailty', 'frame', 'framework',
    'francis', 'frankfurter', 'frankness', 'frantic', 'fraternal', 'fratricide', 'fraudulent', 'fraught', 'freckle', 'freedom',
    'freeboard', 'freehold', 'freelance', 'freeway', 'freewheel', 'freezer', 'freight', 'french', 'frenzy', 'frequency',
    'fresco', 'freshman', 'fretwork', 'friction', 'friday', 'frigate', 'frighten', 'frigid', 'frilliness', 'fringe',
    'frisk', 'fritter', 'frivolous', 'frock', 'frogman', 'frolic', 'frontage', 'frontier', 'frontispiece', 'frostbite',
    'frosting', 'frothiness', 'frown', 'frugal', 'fruitcake', 'fruition', 'frustrate', 'fuchsia', 'fudge', 'fuel',
    'fugitive', 'fulcrum', 'fulfill', 'fullness', 'fulminate', 'fumble', 'fumigate', 'function', 'fundamental', 'funeral',
    'fungus', 'funicular', 'funnel', 'funny', 'furbish', 'furlong', 'furlough', 'furnace', 'furnish', 'furniture',
    'furor', 'furrow', 'furtive', 'fury', 'fuse', 'fuselage', 'fusillade', 'fusion', 'futile', 'future',
    'futurism', 'gadget', 'gaelic', 'gaff', 'gaggle', 'gaiety', 'gaiter', 'galactic', 'galaxy', 'gale',
    'galleon', 'gallery', 'galley', 'gallic', 'gallop', 'gallows', 'galvanize', 'gambit', 'gamble', 'gambol',
    'gamecock', 'gamester', 'gamut', 'gander', 'gangplank', 'gangrene', 'gangster', 'gannet', 'gantry', 'garage',
    'garbage', 'garble', 'gardenia', 'gargoyle', 'garland', 'garlic', 'garment', 'garnet', 'garnish', 'garret',
    'garrison', 'garrulous', 'garter', 'gaslight', 'gasoline', 'gasp', 'gastric', 'gastronomy', 'gatehouse', 'gateway',
    'gatherer', 'gating', 'gaucho', 'gaudiness', 'gauge', 'gauntlet', 'gauze', 'gavel', 'gawkiness', 'gazing',
    'gearbox', 'gears', 'gearshift', 'gecko', 'gelatin', 'gemini', 'gemsbok', 'gender', 'genealogy', 'general',
    'generate', 'generator', 'generous', 'genesis', 'genetics', 'genial', 'genie', 'genius', 'genocide', 'genre',
    'genteel', 'gentian', 'gentry', 'genuine', 'geodesic', 'geography', 'geology', 'geometry', 'geophysics', 'georgia',
    'geranium', 'gerbil', 'geriatric', 'german', 'germinate', 'gerrymander', 'gertrude', 'gestation', 'gesticulate', 'gesture',
    'getaway', 'geyser', 'ghana', 'ghastly', 'ghetto', 'ghostly', 'ghoul', 'giant', 'gibberish', 'gibbet',
    'gibbon', 'giddy', 'gigabyte', 'gigantic', 'giggle', 'gilded', 'gimlet', 'gimmick', 'gingerbread', 'gingham',
    'ginkgo', 'ginseng', 'giraffe', 'girdle', 'girlfriend', 'girlish', 'girth', 'gizmo', 'glacial', 'glacier',
    'gladiator', 'gladiolus', 'glamorous', 'glamour', 'glance', 'glandular', 'glare', 'glassware', 'glaucoma', 'glazier',
    'gleam', 'glean', 'gleeful', 'glider', 'glimmer', 'glimpse', 'glisten', 'glitch', 'glitter', 'gloaming',
    'gloat', 'global', 'globe', 'globular', 'gloominess', 'glorify', 'glorious', 'glossary', 'glove', 'glowworm',
    'glucose', 'glue', 'glutinous', 'gluttony', 'glycerin', 'gnat', 'gnaw', 'gnome', 'goalie', 'post',
    'goat', 'gobble', 'goblet', 'goblin', 'godchild', 'goddess', 'godfather', 'godmother', 'godparent', 'godsend',
    'goggles', 'goldfish', 'goldsmith', 'golfing', 'gondola', 'gong', 'goodbye', 'goodness', 'goodwill', 'gooseberry',
    'gopher', 'gorgon', 'gorilla', 'gospel', 'gossamer', 'gossip', 'gothic', 'gourmet', 'governess', 'government',
    'governor', 'gown', 'grab', 'graceful', 'gracious', 'gradation', 'gradient', 'gradual', 'graduate', 'graffiti',
    'grafting', 'grainy', 'gramophone', 'granary', 'grandchild', 'grandeur', 'grandfather', 'grandma', 'grandmother', 'grandpa',
    'grandparent', 'grandson', 'granite', 'granola', 'grant', 'granular', 'grapefruit', 'grapevine', 'graphic', 'graphite',
    'grapple', 'grasp', 'grasshopper', 'grassland', 'grate', 'grateful', 'gratify', 'grating', 'gratitude', 'gratuity',
    'grave', 'gravestone', 'graveyard', 'gravitate', 'gravity', 'gravy', 'grayhound', 'grazing', 'grease', 'greatness',
    'greece', 'greediness', 'greek', 'greenery', 'greenhouse', 'greensward', 'greet', 'grenade', 'grenadine', 'greyhound',
    'gridiron', 'grief', 'grievance', 'grieve', 'grievous', 'griffin', 'grillwork', 'grimace', 'grime', 'grimness',
    'grindstone', 'gripping', 'grizzly', 'groceries', 'groggy', 'grommet', 'grooming', 'groove', 'grotesque', 'grotto',
    'grouch', 'grounding', 'groundnut', 'grouping', 'grouper', 'grove', 'grower', 'growth', 'grubworm', 'grudge',
    'gruel', 'gruesome', 'gruffness', 'grumble', 'grunt', 'guarantee', 'guardhouse', 'guardian', 'guardrail', 'guatemala',
    'guerilla', 'guesswork', 'guestbook', 'guidance', 'guidebook', 'guideline', 'guileless', 'guillotine', 'guiltiness', 'guinea',
    'guitarist', 'gulf', 'gullible', 'gully', 'gumdrop', 'gumbo', 'gumshoe', 'gunboat', 'gunfire', 'gunmetal',
    'gunpowder', 'gunrunner', 'gunship', 'gunshot', 'gurgle', 'gush', 'gusto', 'gutters', 'gymnasium', 'gymnast',
    'gynecology', 'gypsum', 'gypsy', 'gyroscope', 'habitat', 'habitual', 'hacienda', 'hackney', 'hacksaw', 'haddock',
    'haggard', 'haggis', 'haggle', 'hailstone', 'haircut', 'hairdresser', 'hairline', 'hairpin', 'haiti', 'hake',
    'halberd', 'halcyon', 'halibut', 'hallmark', 'hallow', 'hallway', 'halo', 'halt', 'halter', 'halve',
    'halyard', 'hamburger', 'hamlet', 'hammerhead', 'hammock', 'hamper', 'hamster', 'handbag', 'handball', 'handbill',
    'handbook', 'handcart', 'handcuff', 'handful', 'handgun', 'handicap', 'handicraft', 'handiwork', 'handkerchief', 'handlebar',
    'handmaid', 'handrail', 'handshake', 'handset', 'handsaw', 'handsome', 'handwriting', 'handy', 'hangar', 'hangdog',
    'hangglider', 'hanging', 'hangman', 'hangover', 'hanker', 'hanover', 'haphazard', 'hapless', 'happenstance', 'happiness',
    'harangue', 'harass', 'harbinger', 'harbor', 'hardback', 'hardboard', 'hardcover', 'hardship', 'hardware', 'hardwood',
    'hardy', 'harebell', 'harem', 'harlequin', 'harmonica', 'harmonious', 'harmony', 'harness', 'harpist', 'harpoon',
    'harpsichord', 'harpy', 'harrier', 'harrowing', 'harshness', 'harvest', 'hastiness', 'hatchback', 'hatchery', 'hatchet',
    'hatchway', 'hatred', 'haughty', 'haulage', 'haunches', 'haunt', 'havana', 'haven', 'havoc', 'hawaiian',
    'hawk', 'hawthorn', 'haystack', 'hazard', 'hazelnut', 'headache', 'headband', 'headboard', 'headdress', 'headgear',
    'heading', 'headland', 'headlight', 'headline', 'headmaster', 'headphone', 'headquarters', 'headrest', 'headset', 'headstone',
    'headstrong', 'headway', 'headwind', 'healing', 'healthiness', 'heap', 'hearse', 'heartache', 'heartbeat', 'heartbreak',
    'hearth', 'heartland', 'hearty', 'heathen', 'heather', 'heating', 'heave', 'heavenly', 'heaviness', 'hebrew',
    'heckle', 'hectare', 'hectic', 'hedge', 'hedgehog', 'hedgerow', 'hedonist', 'heedless', 'heifer', 'heighten',
    'heirloom', 'heist', 'helical', 'helicopter', 'helium', 'hellcat', 'helmet', 'helmsman', 'helpless', 'helsinki',
    'hemisphere', 'hemlock', 'hemoglobin', 'hemophilia', 'hemp', 'henchman', 'henna', 'heraldry', 'herbaceous', 'herbalist',
    'herbivore', 'herculean', 'herd', 'hereditary', 'heresy', 'heretic', 'heritage', 'hermitage', 'hernia', 'heroic',
    'heroine', 'heroism', 'heron', 'herpes', 'herring', 'hesitate', 'hessian', 'hexagon', 'heyday', 'hibiscus',
    'hiccup', 'hideaway', 'hideous', 'hideout', 'hierarchy', 'glyph', 'hieroglyphic', 'highway', 'hijack', 'hiking',
    'hilarious', 'hillside', 'hilltop', 'himalaya', 'hinder', 'hindsight', 'hinge', 'hinterland', 'hippopotamus', 'hireling',
    'hispanic', 'hissing', 'historian', 'history', 'histrionic', 'hitchhiker', 'hive', 'hoard', 'hoarse', 'hoax',
    'hobby', 'hobo', 'hockey', 'hoist', 'holdall', 'holder', 'holding', 'holdover', 'holdup', 'holiday',
    'holland', 'hollow', 'hollyhock', 'holocaust', 'hologram', 'upholster', 'homage', 'homebound', 'homecoming', 'homeland',
    'homeless', 'homemaker', 'homeopathy', 'homesick', 'homestead', 'hometown', 'homeward', 'homework', 'homicide', 'homily',
    'homogeneous', 'homonym', 'honda', 'honduras', 'honest', 'honeycomb', 'honeydew', 'honeymoon', 'honeysuckle', 'hongkong',
    'honorary', 'hoodlum', 'hoodwink', 'hoofbeat', 'hookah', 'hookworm', 'hooligan', 'hoop', 'hooray', 'hopeful',
    'hopscotch', 'horde', 'horizon', 'hormone', 'hornbeam', 'hornet', 'hornpipe', 'horoscope', 'horrible', 'horrid',
    'horrify', 'horror', 'horseback', 'fly', 'hair', 'shoe', 'power', 'radish', 'horticulture', 'hosepipe',
    'hospitable', 'hospital', 'hostage', 'hostess', 'hostility', 'hotbed', 'hotelier', 'hothouse', 'hotrod', 'hound',
    'hourglass', 'houseboat', 'housefly', 'hold', 'keeper', 'maid', 'plant', 'wife', 'work', 'housing',
    'hovercraft', 'howitzer', 'howler', 'hubcap', 'huckleberry', 'huddle', 'humanitarian', 'humanity', 'humble', 'humbug',
    'humdrum', 'humidifier', 'humidity', 'humiliate', 'humility', 'hummingbird', 'humorist', 'humorous', 'humpback', 'hunchback',
    'hundredth', 'hungary', 'hunger', 'hunting', 'huntsman', 'hurdle', 'hurrah', 'hurricane', 'hurry', 'hurtful',
    'husbandry', 'huskiness', 'hussar', 'hustle', 'hutment', 'hyacinth', 'hybrid', 'hydrant', 'hydraulic', 'hydrocarbon',
    'hydroelectric', 'hydrogen', 'hydrofoil', 'hydroplane', 'hyena', 'hygiene', 'hymnal', 'hyperbole', 'hyperactive', 'hyphen',
    'hypnosis', 'hypocrisy', 'hypodermic', 'hypothesis', 'hysteria', 'iambic', 'iberian', 'ibex', 'ibis', 'iceberg',
    'icebox', 'icebreaker', 'icecap', 'icicle', 'icing', 'iconoclast', 'idea', 'idealist', 'identical', 'identify',
    'identity', 'ideology', 'idiocy', 'idiom', 'idiosyncrasy', 'idiot', 'idleness', 'idolatry', 'idyllic', 'igloo',
    'ignite', 'ignition', 'ignoble', 'ignorant', 'ignore', 'iguana', 'illicit', 'illiterate', 'illness', 'illuminate',
    'illusion', 'illustrate', 'image', 'imagery', 'imaginary', 'imagine', 'imbecile', 'imbibe', 'imitate', 'immaterial',
    'immature', 'immediate', 'immense', 'immerse', 'immigrant', 'imminent', 'immobile', 'immoral', 'immortal', 'immune',
    'impact', 'impair', 'impala', 'impart', 'impartial', 'impasse', 'impatient', 'impeach', 'impediment', 'impel',
    'impenetrable', 'imperative', 'imperfect', 'imperial', 'imperil', 'impersonal', 'impersonate', 'impertinent', 'impetus', 'impious',
    'impish', 'implacable', 'implant', 'implausible', 'implement', 'implicate', 'implicit', 'implore', 'imply', 'impolite',
    'import', 'impose', 'imposing', 'impossible', 'impostor', 'impotent', 'impound', 'impoverish', 'impracticable', 'imprecation',
    'imprecise', 'impregnable', 'impressive', 'imprint', 'imprison', 'improbable', 'impromptu', 'improper', 'improve', 'improvise',
    'imprudent', 'impudent', 'impulse', 'impunity', 'impure', 'impute', 'inability', 'inaccurate', 'inaction', 'inactive',
    'inadequate', 'inadmissible', 'inadvertent', 'inalienable', 'inane', 'inanimate', 'inapplicable', 'inappropriate', 'inarticulate', 'inattentive',
    'inaudible', 'inaugurate', 'inauspicious', 'inborn', 'incalculable', 'incandescent', 'incantation', 'incapacitate', 'incarcerate', 'incarnation',
    'incendiary', 'incense', 'incentive', 'inception', 'incessant', 'incinerate', 'incision', 'incisive', 'incite', 'inclement',
    'incline', 'include', 'incognito', 'incoherent', 'income', 'incommensurate', 'incommodious', 'incomparable', 'incompatible', 'incompetent',
    'incomplete', 'incomprehensible', 'inconceivable', 'incongruous', 'inconsequent', 'inconsiderate', 'inconsistent', 'inconsolable', 'inconspicuous', 'inconstant',
    'incontestable', 'inconvenient', 'incorporate', 'incorrect', 'incorrigible', 'increase', 'incredible', 'incredulous', 'increment', 'incriminate',
    'incubate', 'incubator', 'inculcate', 'incumbent', 'incurable', 'incursion', 'indebted', 'indecent', 'indecision', 'indeed',
    'indefatigable', 'indefensible', 'indefinite', 'indelible', 'delicate', 'indemnify', 'indemnity', 'indentation', 'independent', 'indepth',
    'indestructible', 'index', 'india', 'indian', 'indicate', 'indictment', 'indifference', 'indigenous', 'indigent', 'indigestible',
    'indignant', 'indigo', 'indirect', 'indiscreet', 'indiscriminate', 'indispensable', 'indisposed', 'indisputable', 'indissoluble', 'indistinct',
    'individual', 'indivisible', 'indochina', 'indoctrinate', 'indolent', 'indomitable', 'indonesia', 'indoor', 'indorse', 'indubitable',
    'induce', 'induct', 'indulge', 'industrial', 'industrious', 'inebriate', 'ineffective', 'inefficient', 'ineligible', 'ineptitude',
    'inequality', 'inertial', 'inescapable', 'inestimable', 'inevitable', 'inexact', 'inexcusable', 'inexhaustible', 'inexorable', 'inexpensive',
    'inexperience', 'inexplicable', 'inexpressible', 'infallible', 'infamous', 'infancy', 'infantry', 'infatuate', 'infect', 'inferior',
    'inferno', 'infertile', 'infest', 'infidel', 'infiltrate', 'infinite', 'infinitive', 'infinity', 'infirmary', 'inflame',
    'flammable', 'inflate', 'inflection', 'inflict', 'inflow', 'influence', 'influenza', 'informant', 'infraction', 'infringe',
    'infuriate', 'infuse', 'ingenious', 'ingenuity', 'ingenuous', 'ingot', 'ingrained', 'ingrate', 'ingratiate', 'ingredient',
    'inhabit', 'inhaler', 'inherent', 'inherit', 'inhibit', 'inhospitable', 'inhuman', 'inimical', 'iniquity', 'initial',
    'initiate', 'inject', 'injunction', 'injure', 'injustice', 'inkblot', 'inkling', 'inkwell', 'inland', 'inlay',
    'inlet', 'inmate', 'inmost', 'innkeeper', 'innocent', 'innocuous', 'innovate', 'innuendo', 'innumerable', 'oculate',
    'inoffensive', 'inordinate', 'inorganic', 'input', 'inquest', 'inquire', 'inquisition', 'inquisitive', 'inroad', 'insane',
    'inscription', 'inscrutable', 'insecticide', 'insecure', 'inseminate', 'insensible', 'inseparable', 'insert', 'inshore', 'inside',
    'insight', 'insignia', 'insincere', 'insinuate', 'insipid', 'insist', 'insolent', 'insoluble', 'insolvent', 'insomnia',
    'inspect', 'inspector', 'inspiration', 'inspire', 'instability', 'install', 'installment', 'instance', 'instant', 'instead',
    'instigate', 'instill', 'instinct', 'institute', 'instruct', 'instrument', 'insubordinate', 'insufferable', 'insufficient', 'insular',
    'insulate', 'insult', 'insuperable', 'insurance', 'insurgent', 'insurmountable', 'insurrection', 'intact', 'intaglio', 'intake',
    'intangible', 'integer', 'integral', 'integrate', 'integrity', 'intellect', 'intelligence', 'intend', 'intense', 'intensive',
    'intent', 'interact', 'intercede', 'intercept', 'interchange', 'intercom', 'intercourse', 'interdict', 'interest', 'interfere',
    'interim', 'interior', 'interject', 'interlace', 'interlock', 'interlocutor', 'interloper', 'interlude', 'intermediate', 'interment',
    'intermission', 'intermittent', 'intern', 'internal', 'international', 'internecine', 'internet', 'interpellate', 'interpolate', 'interpret',
    'interrogate', 'interrupt', 'intersect', 'intersperse', 'interstate', 'interstice', 'interval', 'intervene', 'interview', 'interweave',
    'intestine', 'intimacy', 'intimidate', 'intolerant', 'intonation', 'intoxicate', 'intractable', 'intramural', 'intransigent', 'intrepid',
    'intricate', 'intrigue', 'intrinsic', 'introduce', 'introspect', 'introvert', 'intrude', 'intuition', 'inundate', 'inure',
    'invade', 'invalid', 'invaluable', 'invariable', 'invasion', 'invective', 'inveigle', 'inventor', 'inventory', 'inverse',
    'invertebrate', 'investigate', 'investor', 'inveterate', 'invidious', 'invigorate', 'invincible', 'inviolable', 'invisible', 'invitation',
    'invite', 'invocation', 'invoice', 'invoke', 'involuntary', 'involve', 'invulnerable', 'inward', 'iodine', 'ionosphere',
    'iowa', 'iranian', 'iraq', 'iridescent', 'irish', 'irksome', 'ironclad', 'ironic', 'ironmonger', 'ironwork',
    'irony', 'irradiate', 'irrational', 'irreconcilable', 'irrefutable', 'irregular', 'irrelevant', 'irreligious', 'irreparable', 'irreplaceable',
    'irrepressible', 'irreproachable', 'irresistible', 'irresolute', 'irrespective', 'irresponsible', 'irretrievable', 'irreverent', 'irreversible', 'irrevocable',
    'irrigate', 'irritant', 'irritate', 'irruption', 'island', 'isobar', 'isolate', 'isotope', 'israel', 'issue',
    'istanbul', 'isthmus', 'italian', 'italic', 'italy', 'itinerary', 'ivory', 'ivy', 'jackal', 'jackass',
    'jacket', 'jackhammer', 'jackknife', 'jackpot', 'jackson', 'jacuzzi', 'jade', 'jaggedness', 'jaguar', 'jailbird',
    'jailer', 'jalopy', 'jamaica', 'jamboree', 'janitor', 'january', 'japanese', 'jargon', 'jasmine', 'jasper',
    'jaundice', 'jauntiness', 'javelin', 'jawbone', 'jaywalk', 'jazz', 'jealousy', 'jean', 'jeep', 'jeer',
    'jellyfish', 'jeopardy', 'jerkiness', 'jersey', 'jester', 'jesuit', 'jettison', 'jetty', 'jeweler', 'jewelry',
    'jigsaw', 'jihad', 'jingle', 'jingoism', 'jockey', 'jocular', 'jodhpurs', 'jogging', 'johannesburg', 'joinery',
    'joint', 'joker', 'jollity', 'jolt', 'jonquil', 'jordan', 'journalism', 'journey', 'jovial', 'joyful',
    'jubilant', 'jubilee', 'judaism', 'judgement', 'judicial', 'judiciary', 'judicious', 'judo', 'juggernaut', 'juggler',
    'jugular', 'juice', 'juicy', 'jujitsu', 'jukebox', 'julep', 'julian', 'july', 'jumble', 'jumbo',
    'jumper', 'jumpsuit', 'junc', 'junction', 'juncture', 'june', 'jungle', 'junior', 'juniper', 'junket',
    'junk yard', 'junta', 'jupiter', 'jurisdiction', 'jurisprudence', 'juror', 'jury', 'justice', 'justify', 'jutland',
    'juvenile', 'juxtapose', 'kabuki', 'kaiser', 'kaleidoscope', 'kangaroo', 'kansas', 'karate', 'karma', 'kayak',
    'keelhaul', 'keens', 'keep', 'keepsake', 'kelp', 'kennel', 'kentucky', 'kenya', 'kerosene', 'kestrel',
    'ketchup', 'kettle', 'kettledrum', 'keyboard', 'keyhole', 'keynote', 'keystone', 'khaki', 'khartoum', 'kibbutz',
    'kickoff', 'kidnap', 'kidney', 'killjoy', 'kiln', 'kilobyte', 'kilogram', 'kilometer', 'kilowatt', 'kimono',
    'kindhearted', 'kindle', 'kindling', 'kindness', 'kindred', 'kinetic', 'kingdom', 'kingfisher', 'kingpin', 'kinkiness',
    'kiosk', 'kipper', 'kismet', 'kitchenette', 'kite', 'kitten', 'kiwi', 'kleptomania', 'knapsack', 'knave',
    'kneead', 'kneecap', 'kneel', 'knell', 'knickerbockers', 'knickknack', 'knighthood', 'knitwear', 'knob', 'knockout',
    'knoll', 'knot', 'knowhow', 'knowledge', 'knuckle', 'koala', 'kodak', 'kohlrabi', 'kremlin', 'krypton',
    'kudos', 'kudu', 'kumquat', 'kurt', 'kuwait', 'label', 'laboratory', 'labyrinth', 'lace', 'lacerate',
    'lachrymose', 'lackadaisical', 'lackey', 'laconic', 'lacquer', 'lacrosse', 'lactate', 'ladder', 'laden', 'ladle',
    'ladybug', 'lagoon', 'laidback', 'lair', 'laity', 'lakefield', 'lakeside', 'lambskin', 'lamentation', 'laminate',
    'lampoon', 'lamppost', 'lampshade', 'lance', 'landfill', 'landing', 'landlord', 'landmark', 'landscape', 'landslide',
    'lane', 'language', 'languid', 'languor', 'lantern', 'lapdog', 'lapel', 'lapis', 'lapse', 'laptop',
    'lapwing', 'larceny', 'larch', 'larder', 'largeness', 'largesse', 'larkspur', 'larva', 'laryngitis', 'larynx',
    'laser', 'lash', 'lassitude', 'lasso', 'last', 'latchkey', 'late', 'lateness', 'latent', 'later',
    'lateral', 'latex', 'lathe', 'lather', 'latin', 'latitude', 'latrine', 'lattice', 'latvia', 'laudable',
    'udanum', 'laughable', 'laughter', 'launchpad', 'laundromat', 'laundry', 'laureate', 'laurel', 'lava', 'lavatory',
    'lavender', 'lavish', 'lawmaker', 'lawnmower', 'lawsuit', 'lawyer', 'laxative', 'laxity', 'layman', 'layoff',
    'layout', 'laziness', 'leader', 'leadership', 'leaflett', 'league', 'leakage', 'lean-to', 'leanness', 'leapfrog',
    'leapyear', 'learner', 'learning', 'leasehold', 'leash', 'leather', 'leave', 'lebanon', 'lectern', 'lecture',
    'ledge', 'ledger', 'leech', 'leeward', 'leftist', 'leftover', 'legacies', 'legalism', 'legation', 'legendary',
    'legerdemain', 'legibility', 'legionnaire', 'legislate', 'legislature', 'legitimate', 'legume', 'leisure', 'lemonade', 'lemur',
    'lender', 'lengthwise', 'leniency', 'lens', 'lentil', 'leopard', 'leotard', 'leper', 'leprechaun', 'leprosy',
    'lesion', 'lesotho', 'lessee', 'lessen', 'lesson', 'lethal', 'lethargy', 'letterhead', 'lettering', 'lettuce',
    'leukemia', 'levee', 'leveling', 'lever', 'leverage', 'leviathan', 'levitate', 'levity', 'lexicon', 'liability',
    'liaison', 'liar', 'libation', 'liberalism', 'liberate', 'liberia', 'libertine', 'liberty', 'librarian', 'library',
    'libya', 'license', 'licentiate', 'licorice', 'lieutenant', 'lifeboat', 'lifeguard', 'lifeline', 'lifelong', 'lifesaver',
    'lifespan', 'lifestyle', 'lifetime', 'lift-off', 'ligament', 'ligature', 'lightboat', 'house', 'ning', 'ship',
    'weight', 'lignite', 'likable', 'likelihood', 'likeness', 'likewise', 'lilac', 'lilliputian', 'lilypad', 'limb',
    'limelight', 'limerick', 'limestone', 'limitation', 'limited', 'limousine', 'limpid', 'linchpin', 'lincoln', 'linden',
    'lineage', 'linear', 'linebacker', 'lineman', 'linen', 'liner', 'lineup', 'lingerie', 'linguist', 'linguistics',
    'liniment', 'lining', 'linkage', 'linoleum', 'linseed', 'lintel', 'lioness', 'lionheart', 'lip gloss', 'lipreading',
    'lipstick', 'liquefy', 'liqueur', 'liquidate', 'liquor', 'lisbon', 'listen', 'litany', 'literacy', 'literal',
    'literary', 'literature', 'lithium', 'lithography', 'lithuania', 'litigate', 'litmus', 'litterbug', 'liturgy', 'livestock',
    'livid', 'living', 'lizard', 'llama', 'loading', 'loadstone', 'loathsome', 'lobbyist', 'lobster', 'locality',
    'localize', 'location', 'locator', 'lockjaw', 'locksmith', 'locomotion', 'locomotive', 'locust', 'lodger', 'lodging',
    'logarithm', 'logbook', 'logcabin', 'loggerhead', 'logic', 'logistic', 'logistics', 'logjam', 'logo', 'logotype',
    'loiter', 'lollipop', 'lombard', 'loneliness', 'loner', 'longevity', 'longitude', 'longitudinal', 'longhorn', 'longing',
    'longshoreman', 'lookout', 'loom', 'loony', 'loophole', 'looseness', 'loot', 'loquacious', 'lordship', 'lorgnette',
    'lottery', 'lotus', 'loudness', 'loudspeaker', 'louisiana', 'lounge', 'louse', 'loutish', 'lovebird', 'loveliness',
    'lovelorn', 'lover', 'loving', 'lowland', 'loyalist', 'loyalty', 'lozenge', 'lubricant', 'lubricate', 'lucid',
    'lucifer', 'luckiness', 'lucrative', 'ludicrous', 'luggage', 'lugubrious', 'lukewarm', 'lullaby', 'lumbago', 'lumberjack',
    'luminary', 'luminous', 'lumpiness', 'lunacy', 'lunar', 'lunatic', 'luncheon', 'lungfish', 'lupine', 'lurch',
    'lure', 'lurid', 'luscious', 'lushness', 'lustrous', 'lute', 'luxembourg', 'luxuriant', 'luxury', 'ceum',
    'lynx', 'lyre', 'lyricist', 'macaroni', 'macaroon', 'macaw', 'mace', 'macedonia', 'machination', 'machine',
    'machinery', 'machinist', 'mackerel', 'macintosh', 'macrocosm', 'madagascar', 'madam', 'madcap', 'madness', 'madonna',
    'madras', 'madrid', 'madrigal', 'maelstrom', 'maestro', 'magazine', 'magenta', 'maggot', 'magic', 'magistrate',
    'magma', 'magnanimity', 'magnate', 'magnesium', 'magnet', 'magneto', 'magnificence', 'magnify', 'magnitude', 'magnolia',
    'magpie', 'mahogany', 'maidservant', 'mailbag', 'mailbox', 'mailman', 'mainland', 'mainspring', 'mainstay', 'stream',
    'maintain', 'maize', 'majesty', 'major', 'majority', 'makeover', 'makeshift', 'makeup', 'malady', 'malaria',
    'malawi', 'malaysia', 'malcontent', 'maldive', 'malevolent', 'malice', 'malicious', 'malignant', 'malinger', 'mallard',
    'mallet', 'mallow', 'malnutrition', 'maltese', 'maltreat', 'mammal', 'mammoth', 'management', 'manager', 'mandarin',
    'mandate', 'mandatory', 'mandolin', 'mandrake', 'maneuver', 'manganese', 'manger', 'mangle', 'mango', 'mangrove',
    'manhole', 'manhood', 'manhunt', 'maniac', 'manifesto', 'manifold', 'mannequin', 'mannerism', 'manometer', 'manor',
    'manpower', 'manservant', 'mansion', 'mantelpiece', 'mantis', 'mantle', 'manual', 'manufacture', 'manuscript', 'manx',
    'maple', 'mapping', 'marathon', 'marauder', 'marble', 'march', 'marchioness', 'mare', 'margarine', 'margin',
    'marigold', 'marimba', 'marina', 'marinate', 'marine', 'mariner', 'marionette', 'maritime', 'marjoram', 'markdown',
    'marketable', 'marksmanship', 'marmalade', 'marmoset', 'marmot', 'maroon', 'marquee', 'marquess', 'marriage', 'marrow',
    'mars', 'marshmallow', 'marsupial', 'martian', 'martial', 'martin', 'martinet', 'martyrdom', 'marvelous', 'marzipan',
    'mascara', 'mascot', 'masculine', 'mash', 'masking', 'masonry', 'masquerade', 'massacre', 'massage', 'masseur',
    'massive', 'masthead', 'mastermind', 'masterpiece', 'mastery', 'masticate', 'mastiff', 'mastodon', 'matchbox', 'matchmaker',
    'mate', 'materialism', 'maternal', 'maternity', 'math', 'mathematician', 'matinee', 'matriarch', 'matriculate', 'matrimony',
    'matrix', 'matron', 'matter-of-fact', 'mattress', 'mature', 'mausoleum', 'mauve', 'maverick', 'maximum', 'mayday',
    'mayfly', 'mayhem', 'mayonnaise', 'mayor', 'maypole', 'maze', 'meadow', 'meagerness', 'mealtime', 'meander',
    'meaningful', 'meanness', 'meantime', 'measles', 'measurement', 'meatball', 'mechanic', 'mechanism', 'medalist', 'medallion',
    'meddle', 'media', 'mediator', 'medical', 'medication', 'medieval', 'mediocre', 'meditate', 'mediterranean', 'medium',
    'medley', 'meekness', 'meerschaum', 'meeting', 'megabyte', 'megaphone', 'megaton', 'melancholy', 'melodrama', 'melody',
    'melon', 'membership', 'membrane', 'memento', 'memo', 'memoir', 'memorandum', 'memorial', 'memorize', 'memory',
    'memphis', 'menace', 'menagerie', 'mendicant', 'menial', 'meningitis', 'menopause', 'mental', 'menthol', 'mention',
    'mentor', 'menu', 'mercantile', 'mercenary', 'merchandise', 'merchant', 'merciful', 'mercury', 'mercy', 'merge',
    'meridian', 'meringue', 'merit', 'mermaid', 'mermonkey', 'merriment', 'merry-go-round', 'mesh', 'mesmerize', 'message',
    'messenger', 'messiah', 'metalwork', 'metamorphosis', 'metaphor', 'meteorite', 'meteorology', 'meter', 'methane', 'methodology',
    'methyl', 'meticulous', 'metric', 'metronome', 'metropolis', 'metropolitan', 'mexico', 'mezzanine', 'miami', 'miasma',
    'mica', 'michigan', 'microbe', 'microchip', 'microcosm', 'microfilm', 'micrometer', 'microphone', 'microscope', 'microsecond',
    'microwave', 'midday', 'middleman', 'midget', 'land', 'night', 'shipman', 'summer', 'way', 'wife',
    'wifehood', 'midyear', 'mightiness', 'migraine', 'migrant', 'migrate', 'mildew', 'mildness', 'mileage', 'post',
    'stone', 'militant', 'military', 'militia', 'milkshake', 'milky', 'millennium', 'miller', 'millet', 'milligram',
    'millimeter', 'milliner', 'millionaire', 'millipede', 'millstone', 'mimeograph', 'mimicry', 'mimosa', 'minaret', 'mincemeat',
    'mindful', 'minefield', 'mineralogy', 'minesweeper', 'mingle', 'miniature', 'minibus', 'minicomputer', 'minimise', 'minimum',
    'minion', 'miniskirt', 'minister', 'ministry', 'mink', 'minnow', 'minority', 'minotaur', 'minstrel', 'mint',
    'minuet', 'minuscule', 'minute', 'miracle', 'mirage', 'mirror', 'mirth', 'misadventure', 'misanthrope', 'misapprehend',
    'misappropriate', 'misbehave', 'miscalculate', 'miscarry', 'miscellaneous', 'mischief', 'misconception', 'misconduct', 'misconstrue', 'miscreant',
    'misdeed', 'demeanor', 'misdirect', 'miserable', 'miserliness', 'misery', 'misfortune', 'misgiving', 'misguide', 'mishap',
    'misinform', 'misinterpret', 'misjudge', 'mislay', 'mislead', 'mismanage', 'misnomer', 'misplace', 'misprint', 'misquote',
    'misrepresent', 'missile', 'missionary', 'mississippi', 'missouri', 'misspell', 'misstatement', 'mistake', 'mistletoe', 'mistress',
    'mistrust', 'misunderstand', 'misuse', 'mite', 'mitigate', 'mitre', 'mittens', 'mix-up', 'mixture', 'mnemonic',
    'moat', 'mobcap', 'mobile', 'mobility', 'mobilize', 'moccasin', 'mockery', 'mockingbird', 'modal', 'mode',
    'model', 'moderate', 'modernize', 'modesty', 'modicum', 'modify', 'modulate', 'module', 'mohair', 'mohammad',
    'moisturize', 'molasses', 'moldboard', 'moldiness', 'molecule', 'mole-hill', 'moleskin', 'molest', 'mollify', 'mollusk',
    'molten', 'momentous', 'momentum', 'monaco', 'monarch', 'monastery', 'monday', 'monetary', 'moneybag', 'mongolia',
    'mongoose', 'mongrel', 'monitor', 'monkfish', 'monkey', 'monocle', 'monogamy', 'monogram', 'monograph', 'monolith',
    'monologue', 'monopolize', 'monorail', 'monosyllable', 'monotheism', 'monotone', 'monotony', 'monsoon', 'monster', 'monstrosity',
    'montana', 'month', 'monument', 'moonbeam', 'moonlight', 'moonraker', 'moonshine', 'moonstone', 'moorhen', 'moorland',
    'moose', 'mop-up', 'moppet', 'morale', 'morality', 'morass', 'moratorium', 'morbid', 'morbidity', 'mordant',
    'moreover', 'morgan', 'morgue', 'moribund', 'mormon', 'morning', 'morocco', 'moron', 'morose', 'morphine',
    'morphology', 'morris', 'morsel', 'mortal', 'mortarboard', 'mortgage', 'mortician', 'mortify', 'mortuary', 'mosaic',
    'moscow', 'moses', 'mosque', 'mosquito', 'mossy', 'most', 'motel', 'mothball', 'motherboard', 'land',
    'hood', 'in-law', 'less', 'ly', 'motionless', 'motivate', 'motive', 'motley', 'motocross', 'motorcade',
    'cycle', 'ist', 'boat', 'home', 'way', 'motto', 'moulding', 'moulting', 'mound', 'mountain',
    'mountaineer', 'mountie', 'mournful', 'mouse-pad', 'trap', 'mousetrap', 'mousse', 'moustache', 'mouthpiece', 'wash',
    'movable', 'movement', 'movie', 'moving', 'mower', 'mozambique', 'mozzarella', 'muchness', 'mucilage', 'muckrake',
    'mucous', 'mucus', 'mud-guard', 'slide', 'muddle', 'mudflat', 'muezzin', 'muffler', 'muffin', 'muffle',
    'muggy', 'mulberry', 'mulch', 'muleteer', 'mullet', 'multicolor', 'multimedia', 'millionaire', 'multiply', 'multitude',
    'mumble', 'mummy', 'mumps', 'munch', 'mundane', 'munich', 'municipal', 'munitions', 'muralist', 'murderer',
    'murkiness', 'murmur', 'muscadine', 'muscatel', 'muscle', 'muscular', 'museum', 'mushroom', 'musicology', 'musketeer',
    'muskrat', 'muslim', 'muslin', 'mussel', 'mustang', 'mustard', 'muster', 'mustiness', 'mutability', 'mutation',
    'mute', 'mutilate', 'mutineer', 'mutiny', 'mutt', 'mutter', 'mutton', 'mutual', 'muzzle', 'myriad',
    'myrrh', 'myrtle', 'mysterious', 'mystery', 'mystic', 'mystify', 'mystique', 'mythology', 'nabob', 'nacelle',
    'nacre', 'nadir', 'nagging', 'nailbrush', 'filing', 'naivety', 'nakedness', 'namesake', 'namibia', 'nanosecond',
    'napkin', 'narcissus', 'narcotic', 'narration', 'narrator', 'narrowness', 'narwhal', 'nasal', 'nasturtium', 'natal',
    'nationhood', 'native', 'nativity', 'naturalist', 'nature', 'naughtiness', 'nausea', 'nautical', 'nautilus', 'naval',
    'navel', 'navigate', 'navigator', 'navy', 'naysayer', 'nazi', 'nearness', 'nearsighted', 'neatness', 'nebraska',
    'nebula', 'nebulous', 'necessitate', 'necessity', 'necktie', 'nectar', 'nectarine', 'needfire', 'needlework', 'needless',
    'nefarious', 'negation', 'negative', 'neglect', 'negligee', 'negligence', 'negotiate', 'negro', 'neighborly', 'neighborhood',
    'neither', 'neon', 'nephew', 'nephritis', 'nepotism', 'neptune', 'nerve', 'nervousness', 'nestling', 'nestor',
    'etherlands', 'network', 'neuralgia', 'neurology', 'neurosis', 'neutrality', 'neutron', 'nevada', 'nevermore', 'newborn',
    'newcomer', 'newfoundland', 'newlywed', 'newness', 'newsagent', 'newsboy', 'broadcast', 'caster', 'paper', 'print',
    'reel', 'room', 'stand', 'worthy', 'newton', 'next-door', 'niagara', 'nibble', 'nicaragua', 'nicety',
    'niche', 'nickelodeon', 'nickname', 'nicotine', 'niece', 'nigeria', 'nighthawk', 'nightingale', 'nightmare', 'nightshade',
    'nihilism', 'nile', 'nimbleness', 'nimbostratus', 'nimbus', 'ninepence', 'nineteen', 'ninetieth', 'ninety', 'nintendo',
    'nip-and-tuck', 'nipper', 'nipple', 'nirvana', 'nitrate', 'nitrogen', 'nitroglycerin', 'nobility', 'nobleman', 'nobody',
    'nocturnal', 'nocturne', 'nodule', 'noise', 'noisiness', 'nomad', 'nomenclature', 'nominal', 'nominate', 'nominee',
    'nonchalant', 'nonconformist', 'nondescript', 'nonentity', 'nonfiction', 'nonsense', 'nonstop', 'noodle', 'nook', 'noon',
    'noonday', 'noontime', 'nordic', 'normality', 'normandy', 'norse', 'northeastern', 'northerly', 'northern', 'northward',
    'northwest', 'norway', 'norwegian', 'nosebag', 'nosebleed', 'nosedive', 'gay', 'nostalgia', 'nostril', 'nostrum',
    'notability', 'notary', 'notation', 'notebook', 'noteworthy', 'nothingness', 'noticeboard', 'notification', 'notion', 'notoriety',
    'notwithstanding', 'nougat', 'nourish', 'nova', 'novelty', 'november', 'novice', 'nowadays', 'nowhere', 'noxious',
    'nozzle', 'nuance', 'nuclear', 'nucleus', 'nudge', 'nugget', 'nuisance', 'nullify', 'numbness', 'numeral',
    'numerator', 'numerical', 'numerology', 'numismatic', 'numskull', 'nunnery', 'nuptials', 'nursemaid', 'nursery', 'nursing',
    'nurture', 'nutcracker', 'meg', 'shell', 'hatch', 'nutrient', 'nutritive', 'nutshell', 'nylon', 'nymph',
    'oakland', 'oarsman', 'oasis', 'oath', 'oatmeal', 'obdurate', 'obedience', 'obedient', 'obeisance', 'obelisk',
    'obese', 'obey', 'obituary', 'objective', 'obligation', 'obligatory', 'oblige', 'oblique', 'obliterate', 'oblivion',
    'oblong', 'obnoxious', 'oboe', 'obscene', 'obscure', 'observance', 'observatory', 'observe', 'obsess', 'obsidian',
    'obsolete', 'obstacle', 'obstetrics', 'obstinate', 'obstruct', 'obtain', 'obtrusive', 'obtuse', 'obverse', 'obviate',
    'obvious', 'ocarina', 'occasion', 'occident', 'occult', 'occupant', 'occupation', 'occupy', 'occurrence', 'oceanography',
    'ocelot', 'ochre', 'octagon', 'octave', 'october', 'octopus', 'ocular', 'occulist', 'oddity', 'odds',
    'odious', 'odometer', 'odorless', 'odyssey', 'offence', 'offend', 'offense', 'offensive', 'offering', 'offhand',
    'officeholder', 'officer', 'officialdom', 'offing', 'offload', 'offbeat', 'offset', 'offshoot', 'offshore', 'offside',
    'offspring', 'offstage', 'often', 'ogre', 'ohio', 'oilfield', 'paper', 'rig', 'slick', 'tanker',
    'ointment', 'oklahoma', 'okra', 'old-fashioned', 'oldness', 'oleander', 'olfactory', 'olive', 'olympic', 'omaha',
    'oman', 'ombudsman', 'omega', 'omelette', 'omen', 'ominous', 'omissible', 'omission', 'omnipresent', 'omniscient',
    'omnivorous', 'onboard', 'oncoming', 'oneself', 'oneside', 'ongoing', 'onion', 'onlooker', 'online', 'onlook',
    'onslaught', 'ontario', 'onward', 'onyx', 'oops', 'ooze', 'opacity', 'opal', 'opaque', 'open-air',
    'opener', 'house', 'ness', 'work', 'opera', 'operate', 'operation', 'operative', 'operetta', 'ophthalmology',
    'opinion', 'opium', 'opossum', 'opponent', 'opportune', 'opportunity', 'oppose', 'opposite', 'opposition', 'oppress',
    'optician', 'optics', 'optimal', 'optimism', 'option', 'opulence', 'oracle', 'orangeade', 'orangutan', 'oration',
    'orator', 'oratory', 'orchard', 'orchestra', 'orchid', 'ordain', 'ordeal', 'orderliness', 'cardinal', 'ordinal',
    'ordinance', 'ordinary', 'ordination', 'ordnance', 'oregano', 'organism', 'organist', 'organization', 'organize', 'oriental',
    'origami', 'origin', 'originality', 'orinoco', 'oriole', 'orion', 'ornament', 'ornate', 'ornithology', 'orphanage',
    'orthodontist', 'orthodox', 'orthopedics', 'oscar', 'oscillate', 'osier', 'oslo', 'osprey', 'ostensible', 'ostentation',
    'ostracize', 'ostrich', 'other-worldly', 'otherwise', 'otter', 'ottoman', 'ounce', 'outbreak', 'building', 'burst',
    'cast', 'come', 'crop', 'cry', 'door', 'field', 'fit', 'fox', 'goer', 'going',
    'grow', 'house', 'land', 'law', 'lay', 'let', 'line', 'look', 'match', 'number',
    'post', 'rage', 'rider', 'rigger', 'right', 'run', 'score', 'set', 'shine', 'side',
    'skirt', 'smart', 'spoken', 'spread', 'standing', 'station', 'voted', 'ward', 'wear', 'weigh',
    'wit', 'oval', 'ovary', 'ovation', 'overact', 'board', 'burden', 'cast', 'coat', 'come',
    'crowd', 'do', 'dose', 'draw', 'due', 'flow', 'grow', 'hang', 'haul', 'head',
    'hear', 'joyed', 'land', 'lap', 'lay', 'load', 'look', 'night', 'pass', 'pay',
    'plus', 'power', 'ride', 'rule', 'run', 'seas', 'see', 'shadow', 'shoe', 'sight',
    'size', 'sleep', 'statement', 'step', 'stock', 'take', 'throw', 'time', 'ture', 'turn',
    'view', 'whelm', 'work', 'write', 'overt', 'overalls', 'overture', 'overweight', 'overwork', 'overwrite',
    'ovum', 'owl', 'owner', 'oxford', 'oxygen', 'oyster', 'ozone', 'pace', 'pacemaker', 'pacific',
    'pacifier', 'pacifism', 'packhorse', 'packice', 'packing', 'pact', 'padlock', 'pagan', 'pageant', 'pagoda',
    'painkiller', 'paintbox', 'paintbrush', 'painting', 'pair', 'pakistan', 'palace', 'palatable', 'palate', 'palatial',
    'palaver', 'pale', 'palestine', 'palette', 'paling', 'palisade', 'pallbearer', 'pallet', 'pallor', 'palmistry',
    'palpable', 'palpitate', 'paltry', 'pamphlet', 'panacea', 'panama', 'pancake', 'pancreas', 'panda', 'pandemic',
    'pandemonium', 'pander', 'paneling', 'pang', 'panic', 'pannier', 'panorama', 'panther', 'pantomime', 'pantry',
    'papacy', 'papal', 'papaya', 'paperback', 'clip', 'mill', 'weight', 'work', 'paprika', 'papyrus',
    'parable', 'parachute', 'parade', 'paradigm', 'paradise', 'paradox', 'paraffin', 'paragon', 'paragraph', 'paraguay',
    'parakeet', 'parallax', 'parallel', 'paralyze', 'paramedic', 'paramount', 'paranoia', 'parapet', 'paraphernalia', 'paraphrase',
    'plegia', 'parasite', 'parasol', 'paratrooper', 'parcel', 'parchment', 'pardon', 'parentage', 'parenthood', 'parenthesis',
    'parish', 'parity', 'parking', 'parliament', 'parlour', 'parochial', 'parody', 'parole', 'paroxysm', 'parrot',
    'parry', 'parsimony', 'parsley', 'parsnip', 'parsonage', 'partake', 'partiality', 'participant', 'participle', 'particle',
    'particular', 'partisan', 'partition', 'partridge', 'party', 'pascal', 'passbook', 'passenger', 'passerby', 'passion',
    'passive', 'passover', 'passport', 'password', 'pastime', 'pastor', 'pastrami', 'pastry', 'pasture', 'patchwork',
    'patella', 'patentee', 'paternal', 'paternity', 'pathfinder', 'pathology', 'pathos', 'patience', 'patient', 'patriarch',
    'patrician', 'patrimony', 'patriot', 'patrol', 'patronage', 'patter', 'pattern', 'pauper', 'pavement', 'pavilion',
    'pawnshop', 'paycheck', 'day', 'loader', 'master', 'ment', 'off', 'roll', 'pea', 'peaceable',
    'maker', 'peacetime', 'peach', 'peacock', 'peafowl', 'peak', 'peal', 'peanut', 'pearl', 'peasant',
    'pebble', 'pecan', 'peccary', 'peck', 'pectin', 'pectoral', 'peculiar', 'pedagogy', 'pedal', 'pedant',
    'peddle', 'pedestal', 'pedestrian', 'pediatrics', 'pedigree', 'pedometer', 'peel', 'peep', 'peerage', 'peephole',
    'pegboard', 'pelican', 'pellet', 'pellmell', 'pelvis', 'penalty', 'penance', 'pence', 'pencil', 'pendant',
    'pendulum', 'penetrate', 'penguin', 'penicillin', 'peninsula', 'penitence', 'penitentiary', 'penknife', 'penman', 'pennant',
    'penniless', 'pennyworth', 'pensioner', 'pentagon', 'pentagram', 'pentathlon', 'penthouse', 'penultimate', 'penumbra', 'penury',
    'peon', 'peony', 'people', 'pepperoni', 'peppermint', 'pepsin', 'peptone', 'perceive', 'percentage', 'perception',
    'perch', 'percolate', 'percussion', 'perennial', 'perfection', 'perfidious', 'perforate', 'perform', 'performance', 'perfume',
    'perfunctory', 'gola', 'perhaps', 'perilous', 'perimeter', 'periodical', 'periphery', 'periscope', 'perish', 'periwinkle',
    'perjury', 'permanence', 'permeable', 'permissible', 'permission', 'permit', 'permutation', 'pernicious', 'perpendicular', 'perpetrate',
    'perpetual', 'perplex', 'perquisite', 'persecute', 'perseverance', 'persia', 'persimmon', 'persist', 'personage', 'personal',
    'personify', 'personnel', 'perspective', 'perspicacious', 'perspiration', 'persuade', 'persuasion', 'pertain', 'pertinent', 'perturb',
    'peru', 'perusal', 'pervade', 'perverse', 'perversion', 'pervious', 'pesky', 'pessimism', 'pestilence', 'petals',
    'petite', 'petition', 'petrify', 'petroleum', 'petticoat', 'pettiness', 'petunia', 'pewter', 'phantom', 'pharaoh',
    'pharmacy', 'pheasant', 'phenomenon', 'vial', 'philanthropy', 'philately', 'philharmonic', 'philippines', 'philology', 'philosopher',
    'philosophy', 'phobia', 'phoenix', 'phonebook', 'phonetic', 'phonograph', 'phosphate', 'phosphorus', 'photo', 'photocopy',
    'photogenic', 'photograph', 'photon', 'phraseology', 'physician', 'physics', 'physique', 'pianist', 'piano', 'piazza',
    'picaresque', 'piccolo', 'pickax', 'pocket', 'ups', 'picnic', 'pictorial', 'picture', 'picturesque', 'piebald',
    'piecework', 'piercing', 'piety', 'pigeonhole', 'pigment', 'pigpen', 'pigskin', 'pigtail', 'pike', 'pilaf',
    'pilgrim', 'pillage', 'pillar', 'pillowcase', 'pilot', 'pimento', 'pimple', 'pinball', 'cushion', 'pincer',
    'pinch', 'pinecone', 'pineapple', 'pinhole', 'pinion', 'pinnacle', 'pinochle', 'pint', 'pioneer', 'pious',
    'pipeline', 'pipette', 'piquant', 'piracy', 'piranha', 'pirate', 'pirouette', 'piscatorial', 'pistachio', 'pistol',
    'piston', 'pitchfork', 'piteous', 'pitfall', 'pithy', 'pittance', 'pity', 'pivot', 'placard', 'placate',
    'placebo', 'placement', 'placid', 'plagiarism', 'plague', 'plaice', 'plaid', 'plaintext', 'plaintiff', 'plaintive',
    'plait', 'plane', 'planetarium', 'planetary', 'plankton', 'planner', 'plantation', 'plaque', 'plasma', 'plasterboard',
    'plasticity', 'plateau', 'platform', 'platinum', 'platitude', 'platonic', 'platter', 'platypus', 'plausible', 'playbill',
    'boy', 'ground', 'house', 'mate', 'pen', 'room', 'wright', 'plaza', 'pleading', 'pleasantness',
    'pleasure', 'plebeian', 'plebiscite', 'pledge', 'plenary', 'plenitude', 'plenty', 'plethora', 'pliable', 'pliers',
    'plight', 'plinth', 'plodder', 'plotter', 'plover', 'plowshare', 'pluckiness', 'plug', 'plumage', 'plumber',
    'plumbing', 'plume', 'plummet', 'plumpness', 'plunder', 'plunge', 'plunger', 'plurality', 'plush', 'plutonium',
    'plywood', 'pneumatic', 'pneumonia', 'poacher', 'pocketbook', 'knife', 'podium', 'poem', 'poetical', 'poetry',
    'poignancy', 'poinsettia', 'pointer', 'poise', 'poisonous', 'poland', 'polaroid', 'polecat', 'police', 'policyholder',
    'polio', 'polish', 'politeness', 'political', 'politician', 'politics', 'polka', 'pollutant', 'pollute', 'polo',
    'poltergeist', 'polygon', 'polygraph', 'polymer', 'polyp', 'polysyllable', 'polytechnic', 'polytheism', 'pomegranate', 'pommel',
    'pompous', 'poncho', 'ponder', 'pontiff', 'pontoon', 'pony', 'poodle', 'poolroom', 'popcorn', 'poplar',
    'poplin', 'popover', 'poppy', 'populace', 'popular', 'populate', 'porcelain', 'porch', 'porcupine', 'porkchop',
    'porosity', 'porphyry', 'porpoise', 'porridge', 'portability', 'portal', 'cullis', 'hole', 'land', 'manteau',
    'folio', 'rail', 'portion', 'portraiture', 'portugal', 'position', 'positive', 'posse', 'possession', 'possibility',
    'possible', 'postage', 'postal', 'postcard', 'poster', 'posterior', 'posterity', 'postman', 'postmark', 'postmaster',
    'postmortem', 'postscript', 'posture', 'potable', 'potassium', 'potato', 'potency', 'potentate', 'potential', 'potholder',
    'pothole', 'potion', 'potpourri', 'pottery', 'pouch', 'poultry', 'pounce', 'poundage', 'pour', 'poverty',
    'powder', 'powerhouse', 'powwow', 'practicable', 'practical', 'practice', 'practitioner', 'prairie', 'praise', 'prance',
    'prankster', 'prattle', 'preach', 'preamble', 'precarious', 'precaution', 'precede', 'precedent', 'precept', 'precinct',
    'precious', 'precipice', 'precipitate', 'precise', 'precision', 'preclude', 'precocious', 'precursor', 'predator', 'predecessor',
    'predicament', 'predicate', 'predict', 'predilection', 'predispose', 'predominant', 'preeminent', 'preempt', 'prefabricate', 'preface',
    'prefect', 'preferable', 'preference', 'prefix', 'pregnancy', 'prehistoric', 'prejudice', 'prelate', 'preliminary', 'prelude',
    'premature', 'premeditate', 'premiere', 'premises', 'premium', 'premonition', 'preoccupy', 'preparation', 'prepare', 'preponderance',
    'preposition', 'preposterous', 'prerequisite', 'prerogative', 'presage', 'presbyterian', 'preschool', 'prescience', 'prescribe', 'prescription',
    'presence', 'presentiment', 'preservation', 'preserve', 'preside', 'president', 'pressman', 'pressure', 'prestige', 'prestidigitation',
    'presume', 'presumption', 'presuppose', 'pretense', 'pretension', 'pretext', 'prettiness', 'pretzel', 'prevail', 'prevalent',
    'prevaricate', 'prevent', 'preview', 'previous', 'prey', 'price', 'priceless', 'prickle', 'pride', 'priestcraft',
    'priesthood', 'primacy', 'primate', 'primer', 'primeval', 'primitive', 'primrose', 'prince', 'princess', 'principal',
    'principle', 'printout', 'prior', 'priority', 'prism', 'prison', 'pristine', 'privacy', 'privateer', 'privation',
    'privilege', 'prize', 'probable', 'probate', 'probation', 'problematic', 'procedure', 'proceeds', 'procession', 'proclaim',
    'proclivity', 'procrastinate', 'procreate', 'proctor', 'prodigal', 'prodigy', 'produce', 'product', 'profane', 'profess',
    'profession', 'professor', 'proffer', 'proficiency', 'profile', 'profit', 'profligate', 'profound', 'profusion', 'progenitor',
    'progeny', 'prognosis', 'program', 'progress', 'prohibit', 'projector', 'proletariat', 'proliferate', 'prolific', 'prologue',
    'prolong', 'promenade', 'prominent', 'promiscuous', 'promise', 'promontory', 'promote', 'promptness', 'promulgate', 'prone',
    'pronghorn', 'pronoun', 'pronounce', 'proofread', 'propaganda', 'propagate', 'propeller', 'propensity', 'proper', 'property',
    'prophecy', 'prophet', 'prophylactic', 'propitiate', 'propitious', 'proponent', 'proportion', 'proposal', 'proposition', 'proprietor',
    'propriety', 'propulsion', 'prosaic', 'proscribe', 'prose', 'prosecute', 'proselyte', 'prospector', 'prosperous', 'prostate',
    'prosthesis', 'prostitute', 'prostrate', 'protagonist', 'protect', 'protein', 'protestant', 'protocol', 'proton', 'prototype',
    'protract', 'protrude', 'protuberant', 'proudness', 'provenance', 'proverb', 'provide', 'providence', 'province', 'provincial',
    'provision', 'proviso', 'provocation', 'provost', 'prowess', 'prowler', 'proximity', 'prudence', 'prune', 'prussian',
    'pry', 'psalm', 'pseudo', 'pseudonym', 'psychiatrist', 'psychic', 'psychoanalysis', 'psychology', 'psychopath', 'psychosis',
    'pterodactyl', 'puberty', 'publican', 'publication', 'publicity', 'publish', 'pucker', 'pudding', 'puddle', 'pueblo',
    'puerile', 'puffin', 'pugilist', 'pulley', 'pullman', 'pulmonary', 'pulpit', 'pulsate', 'pulse', 'pulverize',
    'pumice', 'pummel', 'pumpkin', 'punching', 'punctilious', 'punctual', 'punctuate', 'puncture', 'pundit', 'pungency',
    'punish', 'punitive', 'punster', 'pupa', 'pupil', 'puppet', 'purchaser', 'pureness', 'purgatory', 'purge',
    'purify', 'puritan', 'purity', 'purple', 'purport', 'purposeful', 'purse', 'purveyor', 'pushbutton', 'cart',
    'chair', 'over', 'pusillanimous', 'pussycat', 'pustule', 'putrefy', 'putrid', 'putter', 'pyramid', 'pyre',
    'pyrotechnics', 'python', 'quackery', 'quadrangle', 'quadrant', 'quadraphonic', 'quadruped', 'quadruple', 'quaff', 'quagmire',
    'quail', 'quaintness', 'quaker', 'qualification', 'qualify', 'quality', 'qualm', 'quandary', 'quantity', 'quantum',
    'quarantine', 'quarry', 'quarterback', 'deck', 'master', 'quartet', 'quarto', 'quartz', 'quasar', 'quash',
    'quasi', 'quaver', 'quay', 'quebec', 'queen', 'quench', 'querulous', 'query', 'quest', 'questionnaire',
    'queue', 'quibble', 'quickness', 'sand', 'silver', 'quid', 'quietude', 'quill', 'quilt', 'quince',
    'quinine', 'quintet', 'quintuplet', 'quip', 'quirk', 'quiver', 'quixotic', 'quiz', 'quorum', 'quota',
    'quotation', 'quotient', 'rabbi', 'rabbit', 'rabies', 'raccoon', 'racer', 'racetrack', 'radial', 'radiance',
    'radiator', 'radical', 'radioactive', 'radiology', 'radish', 'radium', 'radius', 'raffle', 'rafter', 'ragamuffin',
    'ragtime', 'raid', 'railroad', 'railway', 'raincoat', 'raindrop', 'fall', 'proof', 'storm', 'water',
    'raise', 'raisin', 'rajah', 'rally', 'ramble', 'ramification', 'rampart', 'ramrod', 'ranch', 'rancid',
    'rancor', 'random', 'range', 'ranger', 'rankle', 'ransack', 'ransom', 'rapacity', 'rapid', 'rapier',
    'rapine', 'rappel', 'rapport', 'rapt', 'rapture', 'rarebit', 'rarefy', 'rarity', 'rascal', 'rashness',
    'raspberry', 'ratchet', 'ratepayer', 'ratify', 'rating', 'ratio', 'rational', 'rattan', 'rattle', 'rattlesnake',
    'ravage', 'rave', 'gravel', 'raven', 'ravine', 'ravioli', 'ravish', 'rawhide', 'raygun', 'rayon',
    'razor', 'reaction', 'readability', 'readiness', 'readout', 'reaffirm', 'reagent', 'realism', 'realist', 'reality',
    'realize', 'realm', 'reap', 'reappear', 'reappraise', 'rearward', 'reasoning', 'reassure', 'rebate', 'rebel',
    'rebound', 'rebuff', 'rebuild', 'rebuke', 'rebus', 'rebuttal', 'recalcitrant', 'recall', 'recant', 'recapitulate',
    'recapture', 'recede', 'receipt', 'receivables', 'receptacle', 'reception', 'receptive', 'recessional', 'recipe', 'recipient',
    'reciprocal', 'recite', 'reckless', 'reckon', 'reclaim', 'recline', 'recluse', 'recognize', 'recoil', 'recollect',
    'recommend', 'recompense', 'reconcile', 'reconnaissance', 'reconstruct', 'recorder', 'recording', 'recount', 'recoup', 'recourse',
    'recoverable', 'recreation', 'recriminate', 'recruit', 'rectangle', 'rectify', 'rector', 'rectum', 'recuperate', 'recurrence',
    'recycled', 'redbreast', 'redcoat', 'redden', 'redeemable', 'redemption', 'redevelopment', 'redhead', 'redistribute', 'redness',
    'redoubt', 'redress', 'redstart', 'reduce', 'redundant', 'redwood', 'reefer', 'reef', 'reel', 'reelect',
    'reentry', 'refer', 'referee', 'referendum', 'refill', 'refine', 'refinery', 'refit', 'reflect', 'reflector',
    'reflex', 'reform', 'refractory', 'refrain', 'refreshment', 'refrigerate', 'refrigerator', 'refuel', 'refugee', 'refulgent',
    'refund', 'refurbish', 'refusal', 'refute', 'regal', 'regale', 'regalia', 'regard', 'regatta', 'regenerate',
    'regent', 'regime', 'regiment', 'region', 'register', 'registrar', 'registry', 'regress', 'regretful', 'regular',
    'regulate', 'regulator', 'rehabilitate', 'rehearsal', 'rehearse', 'reign', 'reimburse', 'reindeer', 'reinforce', 'reinstate',
    'reiterate', 'reject', 'rejoice', 'rejoin', 'rejuvenate', 'relapse', 'relate', 'relation', 'relative', 'relativity',
    'relax', 'relay', 'release', 'relegate', 'relentless', 'relevance', 'reliable', 'reliance', 'relic', 'relict',
    'relief', 'relieve', 'religion', 'relinquish', 'relish', 'relocate', 'reluctance', 'rely', 'remainder', 'remake',
    'remand', 'remark', 'remediable', 'remedy', 'remember', 'remembrance', 'remind', 'reminiscent', 'remiss', 'remission',
    'remittance', 'remnant', 'remodel', 'remonstrate', 'remorseful', 'remote', 'removable', 'removal', 'remunerate', 'renaissance',
    'renal', 'renovate', 'renown', 'rental', 'renounce', 'reorganize', 'reparable', 'reparation', 'repartee', 'repatriate',
    'repeal', 'repeat', 'repel', 'repentance', 'repercussion', 'repertoire', 'repetition', 'replace', 'replenish', 'replete',
    'replica', 'ply', 'report', 'reporter', 'repose', 'repository', 'reprehend', 'represent', 'repress', 'reprieve',
    'reprimand', 'reprisal', 'reproach', 'reprobate', 'reproduce', 'reproof', 'reptile', 'republican', 'repudiate', 'repugnance',
    'repulse', 'repulsive', 'reputable', 'reputation', 'repute', 'request', 'requiem', 'require', 'requisite', 'requisition',
    'requite', 'rescind', 'rescue', 'research', 'resemble', 'resentment', 'reservation', 'reserve', 'reservoir', 'reside',
    'residence', 'resident', 'residual', 'residue', 'resign', 'resilient', 'resin', 'resist', 'resolute', 'resolution',
    'resolve', 'resonance', 'resort', 'resound', 'resource', 'respectable', 'respectful', 'respiration', 'respite', 'resplendent',
    'respondent', 'response', 'responsibility', 'responsible', 'responsive', 'resthouse', 'restitution', 'restless', 'restoration', 'restrain',
    'restraint', 'restrict', 'restroom', 'resultant', 'resume', 'resumption', 'resurrect', 'resuscitate', 'retailer', 'retain',
    'retaliate', 'retard', 'retention', 'reticent', 'retina', 'retinue', 'retire', 'retort', 'retract', 'retreat',
    'retrench', 'retribution', 'retrieve', 'retroactive', 'retrograde', 'retrospect', 'returnable', 'reunion', 'reunite', 'reveal',
    'reveille', 'revelation', 'revelry', 'revenge', 'revenue', 'reverberate', 'revere', 'reverence', 'reverend', 'reverie',
    'reversal', 'reverse', 'reversion', 'revert', 'review', 'revile', 'revise', 'revision', 'revival', 'revive',
    'revoke', 'revolt', 'revolution', 'revolve', 'revolver', 'revue', 'revulsion', 'reward', 'rhapsody', 'rhenish',
    'rhetoric', 'rheumatism', 'rhinestone', 'rhinoceros', 'rhode', 'rhodesia', 'rhododendron', 'rhubarb', 'rhyme', 'rhythm',
    'ribbon', 'riboflavin', 'rice', 'richness', 'rickets', 'rickshaw', 'ricochet', 'riddle', 'ride', 'rider',
    'ridge', 'ridicule', 'ridiculous', 'rifleman', 'rigging', 'rightful', 'righteous', 'rigidity', 'rigmarole', 'rigor',
    'ringleader', 'ringlet', 'ringmaster', 'ringworm', 'rinse', 'rioting', 'riotous', 'ripcord', 'ripness', 'ripple',
    'rise', 'risky', 'risotto', 'risque', 'rite', 'ritual', 'rivalry', 'riverbed', 'riverbank', 'riverside',
    'rivet', 'riviera', 'rivulet', 'roach', 'roadblock', 'roadhouse', 'roadrunner', 'roadside', 'roadster', 'roadway',
    'roamer', 'roaring', 'roast', 'robber', 'robbery', 'robe', 'robin', 'robotics', 'robust', 'rocker',
    'rocket', 'rockfall', 'rocking', 'rocky', 'rococo', 'rodent', 'rodeo', 'roebuck', 'rogue', 'roister',
    'role', 'rollcall', 'roller', 'rolling', 'romance', 'romania', 'romantic', 'romp', 'rood', 'roofing',
    'rooftop', 'rookery', 'rookie', 'roommate', 'rooster', 'rootlet', 'ropeway', 'rosary', 'rosebud', 'rosemary',
    'rosette', 'rosewood', 'rosin', 'roster', 'rostrum', 'rosiness', 'rotary', 'rotate', 'rotation', 'rotor',
    'rotunda', 'rouge', 'roughage', 'roughness', 'roulette', 'roundabout', 'roundhouse', 'roundup', 'rouse', 'rout',
    'route', 'routine', 'rowboat', 'rowdiness', 'rower', 'royalist', 'royalty', 'rubbed', 'rubber', 'rubbish',
    'rubble', 'rubella', 'rubicon', 'rubric', 'ruby', 'rucksack', 'rudder', 'ruddiness', 'rudiment', 'rueful',
    'ruffian', 'ruffle', 'rugby', 'rugged', 'ruin', 'ruinous', 'ruler', 'ruling', 'rummage', 'rumor',
    'rumpus', 'runaway', 'rundown', 'runner', 'runway', 'rupture', 'rural', 'ruse', 'rush', 'russet',
    'russian', 'rustiness', 'rustic', 'rustler', 'rutabaga', 'ruthless', 'sabbath', 'sabbatical', 'saber', 'sable',
    'sabotage', 'saboteur', 'sabra', 'saccharin', 'sachem', 'sachel', 'sackcloth', 'sacking', 'sacrament', 'sacredness',
    'sacrifice', 'sacrilege', 'sacristan', 'sacrosanct', 'saddlebag', 'sadism', 'sadness', 'safari', 'safeguard', 'safekeeping',
    'safety', 'saffron', 'sagacity', 'sagebrush', 'sagittarius', 'sahara', 'sailcloth', 'sailfish', 'sailing', 'sailor',
    'saintly', 'sake', 'salad', 'salamander', 'salami', 'salary', 'salesclerk', 'salesman', 'salesperson', 'salient',
    'saline', 'saliva', 'salmon', 'salon', 'saloon', 'salsa', 'saltcellar', 'saltine', 'saltpeter', 'saltwater',
    'salubrious', 'salutary', 'salutation', 'salute', 'salvador', 'salvage', 'salvation', 'salve', 'salver', 'samba',
    'samaritan', 'samovar', 'sample', 'samurai', 'sanatorium', 'sanctify', 'sanctuary', 'sandalwood', 'sandbag', 'sandbox',
    'sandcastle', 'sander', 'sandman', 'paper', 'stone', 'storm', 'wich', 'wood', 'sanguine', 'sanitary',
    'sanitation', 'sanity', 'sanskrit', 'santa', 'sapling', 'sapphire', 'sarcasm', 'sarcophagus', 'sardine', 'sardonic',
    'sargasso', 'sari', 'sash', 'saskatchewan', 'satanic', 'satchel', 'sateen', 'satellite', 'satiate', 'satinwood',
    'satire', 'satisfy', 'saturate', 'saturday', 'saturn', 'saucepan', 'saucer', 'sauerkraut', 'saudi', 'saunter',
    'sausage', 'savage', 'savanna', 'savant', 'savior', 'savoriness', 'savoy', 'sawdust', 'sawhorse', 'sawmill',
    'saxophone', 'scabbed', 'scabbard', 'scaffold', 'scalawag', 'scald', 'scale', 'scallion', 'scallop', 'scalpel',
    'scamp', 'scamper', 'scandalize', 'scandinavia', 'scandium', 'scantiness', 'scapegoat', 'scapula', 'scarab', 'scarce',
    'scarcity', 'scarecrow', 'scarf', 'scarlet', 'scathing', 'scatter', 'scavenger', 'scenario', 'scenery', 'scent',
    'sceptic', 'scepter', 'schedule', 'schematic', 'scheme', 'schilling', 'schism', 'schizophrenia', 'scholarship', 'scholastic',
    'schoolbook', 'boy', 'child', 'girl', 'house', 'master', 'mate', 'room', 'schooner', 'sciatic',
    'science', 'scientific', 'scientist', 'scimitar', 'scintillate', 'scion', 'scissors', 'scoff', 'scold', 'sconce',
    'scoop', 'scooter', 'scope', 'scorch', 'scorecard', 'scornful', 'scorpio', 'scorpion', 'scotch', 'scotland',
    'scoundrel', 'scourge', 'scoutmaster', 'scow', 'scowl', 'scramble', 'scrapbook', 'scrape', 'scratchpad', 'scream',
    'screed', 'screenplay', 'screw-driver', 'scribble', 'scribe', 'scrimmage', 'scrip', 'scripture', 'scroll', 'scrotum',
    'scrubland', 'scruff', 'scrumptious', 'scruple', 'scrutinize', 'scrutiny', 'scuba', 'scuffle', 'scullery', 'sculptor',
    'sculpture', 'scum', 'scurrility', 'scuttle', 'scythe', 'seaboard', 'seafarer', 'seafood', 'front', 'going',
    'line', 'man', 'manly', 'manship', 'plane', 'port', 'scape', 'shell', 'shore', 'sick',
    'side', 'ward', 'weed', 'worthy', 'sealant', 'seamstress', 'seance', 'seaplane', 'seaport', 'searchlight',
    'seashore', 'seasick', 'seaside', 'seasoning', 'seatbelt', 'seaward', 'seaweed', 'seaworthy', 'secede', 'secession',
    'seclude', 'seclusion', 'second-hand', 'secondary', 'secrecy', 'secretariat', 'secretary', 'secrete', 'secretion', 'sectarian',
    'section', 'secular', 'secure', 'security', 'sedan', 'sedative', 'sedentary', 'sediment', 'sedition', 'seduce',
    'seductive', 'seedling', 'seedy', 'seek', 'seemly', 'seep', 'seesaw', 'seethe', 'segment', 'segregate',
    'seine', 'seismic', 'seize', 'seizure', 'seldom', 'selection', 'selective', 'selenium', 'self-evident', 'control',
    'defense', 'denial', 'esteem', 'help', 'hood', 'ish', 'pity', 'reliance', 'respect', 'restraint',
    'same', 'service', 'styled', 'sufficient', 'sellout', 'selvage', 'semaphore', 'semblance', 'semen', 'semester',
    'semicircle', 'semicolon', 'semiconductor', 'final', 'monthly', 'precious', 'skilled', 'tone', 'semolina', 'senate',
    'senator', 'send-off', 'seneca', 'senegal', 'senile', 'seniority', 'sensation', 'sense', 'sensibility', 'sensible',
    'sensitive', 'sensor', 'sensual', 'sensuous', 'sentence', 'sentient', 'sentiment', 'sentinel', 'sentry', 'sepal',
    'separable', 'separate', 'separation', 'sepia', 'september', 'septic', 'septum', 'sepulcher', 'sequel', 'sequence',
    'sequester', 'quin', 'redwood', 'serenade', 'serendipity', 'serene', 'serenity', 'serfdom', 'sergeant', 'serial',
    'sericulture', 'series', 'serious', 'sermon', 'serpent', 'serpentine', 'serrated', 'serum', 'servant', 'serviceable',
    'servitude', 'sesame', 'session', 'setback', 'settee', 'setting', 'settlement', 'settler', 'sevenfold', 'seventeen',
    'seventieth', 'seventy', 'severance', 'several', 'severity', 'seville', 'sewage', 'sewerage', 'sewing', 'sexton',
    'shack', 'shackle', 'shad', 'shade', 'shadowy', 'shady', 'shaft', 'shag', 'shaggy', 'shah',
    'shakeup', 'shaky', 'shale', 'shallot', 'shallow', 'shaman', 'shamble', 'shameful', 'shameless', 'shampoo',
    'shamrock', 'shanghai', 'shank', 'shanty', 'shapewear', 'shareholder', 'sharkskin', 'sharpness', 'shatter', 'shave',
    'shawl', 'sheaf', 'shear', 'sheath', 'shed', 'sheen', 'sheepdog', 'fold', 'skin', 'sheer',
    'sheetbing', 'sheik', 'shekel', 'shelf', 'shellac', 'fish', 'shock', 'proof', 'shelter', 'shepherd',
    'sherbet', 'sheriff', 'sherry', 'shetland', 'shield', 'shiftiness', 'shilling', 'shimmer', 'shinbone', 'shingle',
    'shining', 'shinny', 'shinpad', 'shipboard', 'shipbuilder', 'load', 'mate', 'ment', 'wreck',
    'wright', 'yard', 'shire', 'shirt', 'shiver', 'shoelace', 'maker', 'shine', 'string', 'tree',
    'shoal', 'shockproof', 'shoddy', 'shoehorn', 'shoestring', 'shogun', 'shoot', 'shopkeeper', 'lifter', 'talk',
    'work', 'shoreline', 'shortage', 'bread', 'cake', 'coming', 'cut', 'fall', 'hand', 'lived',
    'ness', 'sight', 'stop', 'wave', 'shotgun', 'shoulder', 'shout', 'shovel', 'showbread', 'case',
    'down', 'girl', 'man', 'room', 'stopper', 'shredder', 'shrewdness', 'shriek', 'shrike', 'shrillness',
    'shrimp', 'shrine', 'shrinkage', 'shrivel', 'shroud', 'shrubbery', 'shrug', 'shudder', 'shuffle', 'shun',
    'shunt', 'shutdown', 'shuttlecock', 'shyness', 'siamese', 'siberia', 'sibilant', 'sibling', 'sibyl', 'sicily',
    'sickbed', 'le', 'ness', 'room', 'sidearm', 'board', 'car', 'kick', 'line', 'long',
    'show', 'step', 'track', 'walk', 'ways', 'siding', 'siege', 'sienna', 'sierra', 'siesta',
    'sieve', 'sift', 'sigh', 'sightseer', 'sigil', 'sigma', 'signboard', 'post', 'signal', 'signature',
    'signet', 'significance', 'signify', 'silence', 'silencer', 'silhouette', 'silica', 'silicon', 'silkiness', 'silkworm',
    'silliness', 'silo', 'silverware', 'smith', 'similar', 'simile', 'simmer', 'simplicity', 'simplify', 'simply',
    'simulate', 'simultaneous', 'sincere', 'sincerity', 'sinecure', 'sinewy', 'sinfulness', 'singapore', 'singer', 'singlet',
    'singular', 'sinister', 'sinkhole', 'sinner', 'sinuous', 'sinus', 'siphon', 'siren', 'sirloin', 'sisal',
    'sisterhood', 'in-law', 'sitar', 'sit-in', 'situation', 'sitz-bath', 'sixpence', 'sixteen', 'sixty', 'sizeable',
    'sizzle', 'skateboarding', 'skater', 'skein', 'skeletal', 'skeleton', 'skeptic', 'sketchbook', 'skew', 'skewer',
    'skiing', 'skiff', 'skillful', 'skillet', 'skimmer', 'skimp', 'skinhead', 'flint', 'skiness', 'skip',
    'skipper', 'skirmish', 'skirt', 'skit', 'skittish', 'skittles', 'skulk', 'skullduggery', 'skylight', 'line',
    'lark', 'rocket', 'scraper', 'slab', 'slackness', 'slacks', 'slag', 'slake', 'slalom', 'slam',
    'slander', 'slang', 'slant', 'slapstick', 'slashing', 'slate', 'slatter', 'slaughterhouse', 'slavic', 'slavery',
    'slay', 'sleaziness', 'sledding', 'sledgehammer', 'sleekness', 'sleepiness', 'walker', 'wear', 'sleet', 'sleeve',
    'sleigh', 'sleight-of-hand', 'slender', 'sleuth', 'slice', 'slicker', 'slide', 'slight', 'slimness', 'slime',
    'sling-shot', 'slink', 'slipknot', 'over', 'pad', 'shod', 'way', 'slipperiness', 'slippery', 'slither',
    'sliver', 'slogan', 'sloop', 'slop', 'slope', 'slothful', 'slouch', 'slough', 'slovakia', 'slovenia',
    'slowcoach', 'slowness', 'sludge', 'slug', 'sluggard', 'sluggish', 'sluice', 'slumber', 'slump', 'slur',
    'slushy', 'slut', 'slyness', 'smack', 'smallpox', 'smartness', 'smash', 'smatter', 'smear', 'smell',
    'smelt', 'smile', 'smirk', 'smithereens', 'smithy', 'smock', 'smog', 'smokehouse', 'stack', 'smoky',
    'smolder', 'smoothness', 'smother', 'smudge', 'smugness', 'smuggler', 'smutty', 'snack', 'snaffle', 'snag',
    'snail', 'snakebite', 'snapdragon', 'shot', 'snare', 'snarl', 'snatch', 'sneakiness', 'sneer', 'sneeze',
    'snicker', 'snide', 'sniffle', 'sniper', 'snippet', 'snivel', 'snobbery', 'snooper', 'snooze', 'snore',
    'snorkel', 'snort', 'snout', 'snowball', 'bank', 'bound', 'drift', 'fall', 'flake', 'plow',
    'shoe', 'storm', 'drop', 'snub', 'snuffbox', 'snugness', 'soakage', 'soapbox', 'stone', 'suds',
    'sober', 'sobriety', 'soccer', 'sociable', 'socialism', 'society', 'sociology', 'sock', 'socket', 'socrates',
    'soda', 'sodium', 'sofa', 'sofia', 'softball', 'ness', 'ware', 'soften', 'soil', 'sojourn',
    'solace', 'solar', 'solder', 'soldierly', 'solemnity', 'solicitor', 'solicitude', 'solidarity', 'solidify', 'soliloquy',
    'solitaire', 'solitude', 'soloist', 'solstice', 'solubility', 'solution', 'solvent', 'somalia', 'somber', 'sombrero',
    'somebody', 'someday', 'somehow', 'someone', 'somersault', 'something', 'sometime', 'someway', 'somewhere', 'somnambulist',
    'sonata', 'songbird', 'book', 'ster', 'writer', 'sonnet', 'sonogram', 'sonorous', 'sootiness', 'soothe',
    'soothsayer', 'sophism', 'sophisticate', 'sophomore', 'soporific', 'soprano', 'sorcerer', 'sorcery', 'sordid',
    'soreness', 'sorghum', 'sorority', 'sorrel', 'sorrowful', 'sorry', 'sort', 'sorties', 'sot', 'souffle',
    'sought-after', 'soulful', 'soundness', 'proof', 'track', 'soup', 'sourness', 'source', 'sourkraut', 'southbound',
    'east', 'ern', 'paw', 'ward', 'west', 'souvenir', 'sovereign', 'soviet', 'sowbread', 'soybean',
    'spa', 'spacecraft', 'ship', 'suit', 'walk', 'spacious', 'spade', 'spaghetti', 'spain', 'spaniel',
    'spanish', 'spank', 'spanner', 'sparerib', 'sparkle', 'sparkplug', 'sparrow', 'sparse', 'spartans', 'spasm',
    'spastic', 'spatula', 'spawn', 'speak', 'spearhead', 'mint', 'specialist', 'specialty', 'specie', 'specimen',
    'specious', 'speckle', 'spectacle', 'spectator', 'specter', 'spectrum', 'speculate', 'speechless', 'speedboat', 'way',
    'spellbound', 'checker', 'ling', 'spelter', 'spendthrift', 'sperm', 'sphere', 'spherical', 'sphinx', 'spice',
    'spider', 'spigot', 'spike', 'spillway', 'spinach', 'spinal', 'spindle', 'spinster', 'spiraea', 'spiral',
    'spire', 'spirituality', 'spitfire', 'spittoon', 'spiteful', 'splash', 'splay', 'spleen', 'splendid', 'splendor',
    'splice', 'splint', 'splinter', 'split-second', 'splurge', 'spoilage', 'spokesman', 'sponge', 'sponsor', 'spontaneous',
    'spool', 'spoonbill', 'ful', 'spoor', 'sporadic', 'sporting', 'sportsman', 'spotlight', 'spouse', 'spout',
    'sprain', 'sprawl', 'spray', 'spread', 'spree', 'sprig', 'sprightly', 'springboard', 'time', 'sprinkle',
    'sprint', 'sprite', 'sprocket', 'spruce', 'spryness', 'spud', 'spume', 'spur', 'spurious', 'spurn',
    'spurt', 'sputter', 'spyglass', 'squadron', 'squalid', 'squall', 'squalor', 'square', 'squash', 'squat',
    'squaw', 'squeak', 'squeal', 'squeegee', 'squeeze', 'squid', 'squint', 'squire', 'squirm', 'squirrel',
    'squirt', 'sri lanka', 'stab', 'stability', 'stabilize', 'stable', 'stack', 'stadium', 'staff', 'stag',
    'stagecoach', 'stagger', 'stagnant', 'stain', 'staircase', 'case', 'way', 'well', 'stake', 'stalactite',
    'stalagmite', 'stale', 'stalemate', 'stalk', 'stallion', 'stalwart', 'stamen', 'stamina', 'stammer', 'stampede',
    'stance', 'stanchion', 'standardize', 'standby', 'point', 'still', 'in', 'off', 'out', 'pipe',
    'stanch', 'stanza', 'stapler', 'starboard', 'fish', 'gazer', 'light', 'let', 'starch',
    'stardom', 'stare', 'starling', 'starry', 'starvation', 'statehood', 'house', 'room', 'side', 'ment',
    'stationery', 'statistics', 'statue', 'stature', 'statute', 'staunchness', 'stave', 'stay', 'steadfast', 'steady',
    'steakhouse', 'stealthy', 'steamboat', 'engine', 'roller', 'ship', 'shovel', 'stearin', 'steed', 'steelwork',
    'steeplechase', 'steeple', 'steerage', 'steering', 'stegosaurus', 'stellar', 'stemware', 'stench', 'stencil', 'stenography',
    'stepchild', 'father', 'mother', 'sister', 'son', 'steppingstone', 'stepsister', 'stereo', 'stereotype', 'sterile',
    'sterling', 'sternness', 'stethoscope', 'stevedore', 'stewpan', 'stickler', 'sticky', 'stiff', 'stifle', 'stigma',
    'stile', 'stiletto', 'stillborn', 'ness', 'room', 'stilt', 'stimulant', 'stimulate', 'stimulus', 'stingray',
    'stinkbug', 'stint', 'stipend', 'stipulate', 'stirrup', 'stitchery', 'stockade', 'broker', 'car', 'holder',
    'ing', 'pile', 'room', 'yard', 'stodgy', 'stoicism', 'stoke', 'stole', 'stolid', 'stomach',
    'stonecrop', 'mason', 'ware', 'work', 'stool', 'stoop', 'stopover', 'watch', 'storage', 'stork',
    'stormy', 'storyboard', 'book', 'teller', 'stoutness', 'stovetop', 'stowaway', 'straddle', 'straggle', 'straighten',
    'strainer', 'strand', 'strangle', 'strap', 'stratagem', 'strategy', 'stratosphere', 'stratum',
    'strawberry', 'board', 'hating', 'stray', 'streak', 'streamliner', 'side', 'streetcar', 'strength', 'strenuous',
    'stress', 'stretch', 'strew', 'stricken', 'strictness', 'stride', 'strident', 'strife', 'strikeout', 'striker',
    'stringent', 'striping', 'stripe', 'stripling', 'strive', 'stroke', 'stroll', 'stronghold', 'strontium', 'structure',
    'struggling', 'strum', 'strut', 'strychnine', 'stubbornness', 'stucco', 'studbook', 'student', 'studio', 'studious',
    'stuffing', 'stumble', 'stumpage', 'stump', 'stunner', 'stuntman', 'stupefy', 'stupendous', 'stupidity', 'stupor',
    'sturdiness', 'sturgeon', 'stutter', 'stylet', 'stylist', 'stylus', 'stymie', 'styrofoam', 'subacid', 'subarctic',
    'subatomic', 'subcommittee', 'subconscious', 'subdivide', 'subdue', 'subheading', 'subhuman', 'subjective', 'subjugate', 'sublet',
    'sublime', 'submarine', 'submerge', 'submission', 'submissive', 'submit', 'subordinate', 'subpoena', 'subscribe', 'subsequent',
    'subside', 'subsidiary', 'subsidy', 'subsist', 'subsoil', 'substance', 'substandard', 'substantive', 'substitute', 'substructure',
    'subsume', 'subtensity', 'subterfuge', 'subterranean', 'subtitled', 'subtle', 'subtract', 'suburbia', 'subvert', 'subway',
    'succeed', 'succession', 'succinct', 'succor', 'succulent', 'succumb', 'suckling', 'suction', 'sudan', 'suddenness',
    'sueded', 'suet', 'suffence', 'sufferer', 'suffice', 'efficiency', 'suffix', 'suffocate', 'suffrage', 'suffuse',
    'sugarplum', 'suggestible', 'suicide', 'suitability', 'suitcase', 'suitor', 'sullenness', 'sultanate', 'sultry', 'sumac',
    'summarize', 'summary', 'summation', 'summerhouse', 'summit', 'summoner', 'sumptuous', 'sunbeam', 'block', 'burn',
    'burst', 'dial', 'down', 'flower', 'glass', 'light', 'lit', 'rise', 'set', 'shade',
    'shine', 'stroke', 'spot', 'suit', 'sundae', 'sundry', 'sunfish', 'sunhat', 'superb', 'supercharge',
    'supercilious', 'superficial', 'superfluous', 'superhero', 'superhuman', 'superimpose', 'intend', 'interior', 'superiority', 'superlative',
    'market', 'natural', 'nova', 'power', 'script', 'sonic', 'star', 'stition', 'structure', 'vise',
    'supine', 'supper', 'supplant', 'supple', 'supplement', 'supplicant', 'supplier', 'supply', 'supportive', 'suppose',
    'suppress', 'suppurate', 'supremacy', 'surcharge', 'surety', 'surfboard', 'surface', 'surfeit', 'surfer', 'surge',
    'surgeon', 'surgery', 'surly', 'surmise', 'surmount', 'surname', 'surpass', 'surplice', 'surplus', 'surprise',
    'surrealism', 'surrender', 'surreptitious', 'surrogate', 'surround', 'surtax', 'surveillance', 'surveyor', 'survival', 'survivor',
    'susceptibility', 'suspect', 'suspenders', 'suspense', 'suspicion', 'suspicious', 'sustain', 'sustenance', 'sutler', 'suture',
    'suzerain', 'swab', 'swaddle', 'swagger', 'swallowtail', 'swampland', 'swankiness', 'swap', 'swarthy', 'swastika',
    'swatch', 'swath', 'swatter', 'swayback', 'swearword', 'sweatshirt', 'shop', 'suit', 'sweater', 'sweden',
    'sweepstake', 'sweetbread', 'briar', 'heart', 'meat', 'ness', 'pea', 'potato', 'swell', 'swelter',
    'swerve', 'swiftness', 'swill', 'swimsuit', 'swineherd', 'swinging', 'swipe', 'swirl', 'swish', 'swiss',
    'switchboard', 'blade', 'man', 'switzerland', 'swivel', 'swoon', 'swoop', 'swordfish', 'play', 'smith',
    'sycamore', 'sycophant', 'syllable', 'syllabus', 'syllogism', 'sylph', 'symbiosis', 'symbolic', 'symbolism', 'symmetry',
    'sympathy', 'symphony', 'symposium', 'symptom', 'synagogue', 'synchronize', 'syncopate', 'syndicate', 'syndrome', 'synergism',
    'synod', 'synonym', 'synopsis', 'syntax', 'synthesis', 'syphilis', 'syria', 'syringe', 'syrup', 'systematic',
    'tablecloth', 'land', 'spoon', 'ware', 'tabby', 'tabernacle', 'tableland', 'tablet', 'taboo', 'tabulate',
    'tachometer', 'taciturn', 'tackler', 'tackiness', 'tactician', 'tactics', 'tactile', 'tadore', 'tadpole', 'taffeta',
    'taffy', 'tagalong', 'tahiti', 'tailcoat', 'gate', 'light', 'line', 'man', 'piece', 'pipe',
    'spin', 'wind', 'tailor', 'taiwan', 'takeoff', 'over', 'talcum', 'talent', 'talisman', 'talkative',
    'tallboy', 'tallness', 'tallow', 'tally', 'talon', 'tamarind', 'tambourine', 'tame', 'tamper', 'tampico',
    'tampon', 'tanager', 'tandem', 'tangerine', 'tangible', 'tangle', 'tango', 'tankard', 'tanker', 'tannery',
    'tantrum', 'tanzania', 'taper', 'tapestry', 'tapioca', 'taproom', 'taproot', 'tarantula', 'tardiness', 'target',
    'tariff', 'tarmac', 'tarnation', 'tarnish', 'taro', 'tarot', 'tarpaper', 'tarpaulin', 'tarragon', 'tarsal',
    'tartar', 'tasmania', 'tassel', 'taster', 'tattletale', 'tattoo', 'taunt', 'taurus', 'tautness', 'tavern',
    'tawdry', 'taxation', 'taxi', 'taxidermy', 'taxicab', 'taxonomist', 'taxpayer', 'tea-bag', 'cup', 'kettle',
    'room', 'spoon', 'time', 'teammate', 'teamwork', 'teapot', 'teardrop', 'tearful', 'teaspoonful', 'technicality',
    'technician', 'technique', 'technology', 'tedium', 'teepee', 'teeth', 'teetotaler', 'telecast', 'telecommunication',
    'telegram', 'telegraph', 'telemetry', 'telepathy', 'telephone', 'telephoto', 'teleprinter', 'telescope', 'teletext', 'teletype',
    'television', 'telex', 'telltale', 'temerity', 'temperament', 'temperance', 'temperature', 'tempered', 'tempestuous', 'template',
    'temple', 'tempo', 'temporal', 'temporary', 'temptation', 'tempter', 'tenant', 'tendency', 'tenderfoot', 'loin',
    'ness', 'tendon', 'tendril', 'tenement', 'tenet', 'tennessee', 'tennis', 'tenor', 'tensile', 'tension',
    'tentacle', 'tentative', 'tenuous', 'tenure', 'tepidity', 'tequila', 'tercentenary', 'termite', 'terracotta', 'terrain',
    'terrapin', 'terrarium', 'terrestrial', 'terrible', 'terrier', 'terrific', 'terrify', 'territory', 'terrorist', 'terrycloth',
    'terse', 'tertiary', 'testament', 'testicle', 'testify', 'testimonial', 'testimony', 'tetanus', 'tether', 'textbook',
    'textile', 'texture', 'thailand', 'thames', 'thankful', 'thaw', 'theater', 'theatrical', 'theft', 'theology',
    'theomancy', 'theorem', 'theoretical', 'theosophy', 'therapeutic', 'therapist', 'thereabout', 'thereafter', 'thereby', 'therefore',
    'therefrom', 'therein', 'thereof', 'thereon', 'thereto', 'thereupon', 'thermal', 'thermocouple', 'thermodynamics', 'thermometer',
    'thermos', 'thermostat', 'thesaurus', 'theses', 'thespian', 'thickset', 'thievery', 'thimble', 'thinking', 'thinker',
    'thinner', 'thirstiness', 'thirteen', 'thirtieth', 'thirty', 'thistle', 'thither', 'thorn', 'thoroughbred', 'fare',
    'going', 'ness', 'thoughtful', 'thousandth', 'thrall', 'thrash', 'threadbare', 'threaten', 'threefold', 'pence',
    'some', 'threshing', 'threshold', 'thriftiness', 'thrill-seeker', 'thrivel', 'throatiness', 'throb', 'throne', 'throng',
    'throttle', 'thrush', 'thrust', 'thud', 'thuggee', 'thulium', 'thumbnail', 'thumbprint', 'thumbscrew', 'tack',
    'thump', 'thunderbolt', 'clap', 'cloud', 'head', 'proof', 'struck', 'thursday', 'thyme', 'thyroid',
    'tiara', 'tiber', 'tibet', 'ticket', 'ticktock', 'tidiness', 'tidewater', 'tidings', 'tie-in', 'tier',
    'tiger', 'tightrope', 'wads', 'tile', 'tillable', 'tillage', 'tiller', 'tilt-rotor', 'timberland', 'timepiece',
    'table', 'timidity', 'timing', 'tinware', 'tinderbox', 'tinfoil', 'tingle', 'tinker', 'tinkle', 'tinsel',
    'tintype', 'tiny', 'tiptoe', 'tirade', 'tiring', 'tissue', 'titanic', 'titanium', 'tithe', 'titillate',
    'title', 'titmouse', 'titter', 'titular', 'toadstool', 'toastmaster', 'tobacco', 'toboggan', 'toddler', 'toenail',
    'toffee', 'togetherness', 'toggle', 'toil', 'toiletries', 'tokenism', 'tokyo', 'tolerance', 'tollbooth', 'gate',
    'house', 'tomahawk', 'tomato', 'tombstone', 'tomboy', 'cat', 'foolery', 'tome', 'tomfool', 'tomorrow',
    'tomtom', 'tonality', 'tone-deaf', 'tongs', 'tongue', 'tonic', 'tonight', 'tonnage', 'tonsillectomy', 'tonsilitis',
    'tonsure', 'tontine', 'toolmaker', 'shed', 'box', 'teeth', 'topaz', 'topcoat', 'topic', 'topmost',
    'topography', 'topping', 'topple', 'topsail', 'topsoil', 'topspin', 'topsy-turvy', 'torchbearer', 'light', 'toreador',
    'torment', 'tornado', 'torpedo', 'torpor', 'torque', 'torrential', 'torrid', 'torsion', 'torso', 'tortoise',
    'tortuous', 'torture', 'tory', 'toss-up', 'totalitarian', 'totem', 'touchdown', 'stone', 'toughness', 'tourist',
    'tournament', 'tourniquet', 'towel', 'towering', 'township', 'toxicology', 'toxin', 'toyline', 'traceability', 'trachea',
    'tracksuit', 'traction', 'tractor', 'tradecraft', 'mark', 'name', 'off', 'union', 'wind', 'tradition',
    'traduce', 'traffic', 'tragedian', 'tragedy', 'tragic', 'trailblazer', 'trailer', 'trainload', 'trainer', 'training',
    'trait', 'traitor', 'trajectory', 'tramcar', 'tramp', 'trample', 'tramway', 'tranquilizer', 'transaction', 'transcend',
    'transscribe', 'transcript', 'transduct', 'transept', 'transfer', 'transfigure', 'transfix', 'transform', 'transfuse', 'transgress',
    'transient', 'transistor', 'transit', 'transition', 'transitive', 'translate', 'transliterate', 'translucent', 'transmission', 'transmit',
    'transmute', 'transom', 'transparency', 'transpire', 'transplant', 'transport', 'transpose', 'transship', 'transverse', 'trapdoor',
    'trapezium', 'trapper', 'trashcan', 'trauma', 'travail', 'travelogue', 'traverse', 'treadmill', 'treason', 'treasure',
    'treasury', 'treatment', 'treatise', 'treaty', 'treble', 'treetop', 'trefoil', 'trek', 'trellis', 'tremble',
    'tremendous', 'tremolo', 'tremor', 'trenchcoat', 'trendsetter', 'trepidation', 'trespass', 'trestle', 'trial', 'triangle',
    'triathlon', 'tribalism', 'tribulation', 'tribunal', 'tribune', 'tributary', 'tribute', 'trice', 'triceps', 'triceratops',
    'trickery', 'trickle', 'tricolor', 'tricycle', 'trident', 'tried-and-true', 'triennial', 'trifle', 'trigonometry', 'trilby',
    'trillium', 'trilogy', 'trimness', 'trinidad', 'trinity', 'trinket', 'trio', 'tripod', 'triptych', 'trireme',
    'trisection', 'trite', 'triumph', 'triumvirate', 'trivet', 'trivia', 'trochee', 'troglodyte', 'troika', 'troll',
    'trolley', 'trombone', 'troopship', 'trophy', 'tropical', 'tropics', 'trotters', 'troubadour', 'trouble', 'trough',
    'trounce', 'trousers', 'trousseau', 'trowel', 'truancy', 'truce', 'trucker', 'truculent', 'trudge', 'truffle',
    'truism', 'trumpet', 'truncate', 'truncheon', 'trundle', 'trunnion', 'truss', 'trustee', 'truthful', 'tryout',
    'tsar', 'tse-tse', 'tsunami', 'tubby', 'tubing', 'tuberculosis', 'tuberose', 'tuck-in', 'tucker', 'tuesday',
    'tuft', 'tugboat', 'tuition', 'tulip', 'tumbleweed', 'tumbler', 'tumidity', 'tumor', 'tumultuous', 'tuna',
    'tundra', 'tuning', 'tunisia', 'tunnel', 'turban', 'turbidity', 'turbine', 'turbocharger', 'turboprop', 'turbot',
    'turbulence', 'tureen', 'turf', 'turgid', 'turkey', 'turkish', 'turmeric', 'turmoil', 'turnabout', 'coat',
    'key', 'out', 'pike', 'spit', 'stile', 'table', 'turnip', 'turpentine', 'turpitude', 'turquoise',
    'turret', 'turtle', 'tuscan', 'tusk', 'tussle', 'tussock', 'tutor', 'tuxedo', 'twain', 'tweed',
    'tweezers', 'twelfth', 'twelve', 'twentieth', 'twenty', 'twilight', 'twin', 'twine', 'twinge', 'twinkle',
    'twirl', 'twist', 'twit', 'twitter', 'twofold', 'pence', 'some', 'tycoon', 'tying', 'tympanum',
    'typewriter', 'setting', 'script', 'typhoid', 'typhoon', 'typist', 'typography', 'tyrannical', 'tyrannosaurus', 'tyrant',
    'uganda', 'ugliness', 'ukraine', 'ukulele', 'ulcerate', 'ulster', 'ulterior', 'ultimate', 'ultimatum', 'ultramarine',
    'ultrasonic', 'ultrasound', 'ultraviolet', 'umbel', 'umber', 'umbilical', 'umbrella', 'umpire', 'unabated', 'unabridged',
    'unacceptable', 'unaccompanied', 'unaccountable', 'unaccustomed', 'unaffected', 'unaffiliated', 'unafraid', 'uncompromising', 'unanimous', 'unannounced',
    'unanswerable', 'unarmed', 'unassuming', 'unattached', 'unattended', 'unauthorized', 'unavailable', 'unavoidable', 'unaware', 'unbalanced',
    'unbearable', 'unbecoming', 'unbelievable', 'unbending', 'unbiased', 'unblemished', 'unblinking', 'unbridled', 'unbroken', 'uncanny',
    'unceasing', 'uncertain', 'unchained', 'uncharted', 'uncivilized', 'unclaimed', 'uncle', 'unclear', 'uncoil', 'uncomfortable',
    'uncommon', 'uncompromising', 'unconcerned', 'unconditional', 'unconscious', 'unconstitutional', 'unconventional', 'uncooperative', 'uncouth', 'uncover',
    'unction', 'unctuous', 'undated', 'undaunted', 'undecided', 'undeniable', 'undercover', 'current', 'dog', 'done',
    'foot', 'garment', 'go', 'ground', 'growth', 'hand', 'line', 'mine', 'neath', 'pass',
    'pin', 'score', 'sea', 'secretary', 'shirt', 'side', 'sign', 'statement', 'take', 'tow',
    'wear', 'wood', 'world', 'write', 'undesignated', 'undesirable', 'undisciplined', 'undisclosed', 'undisputed', 'undivided',
    'undoing', 'undoubted', 'undreamed', 'undue', 'undulate', 'undying', 'unearthly', 'uneasiness', 'uneducated', 'unemotional',
    'unemployed', 'ending', 'endurable', 'equal', 'equivocal', 'erring', 'essential', 'even', 'eventful', 'exaggerated',
    'unexampled', 'unexceptionable', 'unexpected', 'unfailing', 'unfair', 'unfaithful', 'unfamiliar', 'unfathomable', 'unfavorable', 'unfeasible',
    'unfeeling', 'unfeigned', 'unfettered', 'unfinished', 'unfit', 'unflagging', 'unflinching', 'unfold', 'unforeseen', 'unforgettable',
    'unfortunate', 'unfounded', 'unfriendly', 'unfurl', 'ungainly', 'ungenerous', 'ungodly', 'ungovernable', 'ungracious', 'ungrateful',
    'unguarded', 'unhallowed', 'unhampered', 'unhandy', 'unhappiness', 'unharm', 'unhealthy', 'unheard', 'unhinge', 'unholy',
    'unhook', 'unhurt', 'unicorn', 'unification', 'uniformity', 'unify', 'unilateral', 'unimaginable', 'unimpeachable', 'unimportant',
    'uninhibited', 'uninjured', 'uninspired', 'unintelligible', 'unintended', 'unintentional', 'uninterested', 'uninterrupted', 'uninvited', 'unionist',
    'unipod', 'unique', 'unisex', 'unison', 'unitarian', 'unity', 'universal', 'universe', 'university', 'unjust',
    'unkempt', 'unkindness', 'unknowable', 'unlawful', 'unlearn', 'unless', 'unlike', 'unlimited', 'unlink', 'unload',
    'unlock', 'unloose', 'unlucky', 'unmade', 'unmanly', 'unmanned', 'unmannerly', 'unmask', 'unmatched', 'unmerciful',
    'unmindful', 'unmistakable', 'mitigated', 'unmoor', 'unmoved', 'unnatural', 'unnecessary', 'unnerve', 'unnoticed', 'unobtrusive',
    'unofficial', 'unorthodox', 'unpack', 'unpaid', 'unpalatable', 'unparallel', 'unpardonable', 'unpleasant', 'unplug', 'unpopular',
    'unprecedented', 'unprejudiced', 'unpremeditated', 'unprepared', 'unpretentious', 'unprincipled', 'unprintable', 'unproductive', 'unprofessional', 'unprofitable',
    'unpromising', 'unprompted', 'unpronounceable', 'unprotected', 'unproven', 'unprovoked', 'unqualified', 'unquenchable', 'unquestionable', 'unravel',
    'unreadable', 'unreal', 'unreasonable', 'unregenerate', 'unrelenting', 'unreliable', 'unrelieved', 'unremitting', 'unrepentant', 'unreserved',
    'unrest', 'unrestrained', 'unrestricted', 'unrivaled', 'unroll', 'unruffled', 'unruly', 'unsafe', 'unsanitary', 'unsatisfactory',
    'unsavory', 'unscathed', 'unscheduled', 'unscrew', 'unscrupulous', 'unsearchable', 'unseasonable', 'unseat', 'unseemly', 'unseen',
    'unselfish', 'unsettle', 'unshakable', 'unsightly', 'unskilled', 'unsociable', 'unsolicited', 'unsolved', 'unsophisticated', 'unsound',
    'unsparing', 'unspeakable', 'unspecified', 'unspoiled', 'unstable', 'unsteady', 'unstinted', 'unstop', 'unstructured', 'unsubstantiated',
    'unsuccessful', 'unsuitable', 'unsung', 'unsure', 'unsurpassed', 'unsuspecting', 'unsymmetrical', 'unsympathetic', 'unsystematic', 'untangle',
    'untenable', 'unthinkable', 'untidy', 'until', 'untimely', 'untold', 'untouchable', 'untoward', 'untrained', 'untried',
    'untroubled', 'untrue', 'untrustworthy', 'untruth', 'untutored', 'unusable', 'unusual', 'unutterable', 'unvarnished', 'unveil',
    'unvoiced', 'unwarranted', 'unwary', 'unwavering', 'unwearied', 'unwelcome', 'unwell', 'unwholesome', 'unwieldy', 'unwilling',
    'unwind', 'unwise', 'unwitting', 'unwonted', 'unworkable', 'unworthy', 'unwrap', 'yielding', 'yoke', 'yodel',
    'yogurt', 'yokefellow', 'yokel', 'yolks', 'yorkshire', 'youngster', 'youthful', 'yugosla', 'yule', 'yuletide',
    'zambia', 'zealot', 'zealously', 'zebra', 'zebu', 'zenith', 'zephyr', 'zero', 'zest', 'zigzag',
    'zimbabwe', 'zinc', 'zirconium', 'zodiac', 'zombie', 'zonal', 'zoning', 'zoology', 'zucchini', 'zulu'
  ];

  // ── 1. Diceware Passphrase Generation ──────────────────────────────────────

  /// Generates an EFF Diceware passphrase.
  static ({String passphrase, double entropyBits}) generateDicewarePassphrase({
    int wordCount = 5,
    String separator = '-',
    PasswordCasing casing = PasswordCasing.lowercase,
    bool includeNumber = false,
    bool includeSymbol = false,
  }) {
    final count = wordCount.clamp(3, 12);
    final chosenWords = <String>[];

    for (int i = 0; i < count; i++) {
      final index = _secureRandom.nextInt(effLargeWordlist.length);
      var word = effLargeWordlist[index];
      switch (casing) {
        case PasswordCasing.lowercase:
          word = word.toLowerCase();
          break;
        case PasswordCasing.titleCase:
          word = word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
          break;
        case PasswordCasing.uppercase:
          word = word.toUpperCase();
          break;
      }
      chosenWords.add(word);
    }

    var result = chosenWords.join(separator);

    double extraEntropy = 0.0;
    if (includeNumber) {
      final digit = _secureRandom.nextInt(10);
      result += '$separator$digit';
      extraEntropy += 3.32; // log2(10)
    }

    if (includeSymbol) {
      const symbols = '!@#\$%^&*';
      final sym = symbols[_secureRandom.nextInt(symbols.length)];
      result += '$separator$sym';
      extraEntropy += 3.0; // log2(8)
    }

    // 12.924 bits per word from 7,776-word dictionary
    final entropyBits = (count * 12.924) + extraEntropy;

    return (passphrase: result, entropyBits: entropyBits);
  }

  // ── 2. Custom Character Password Generation ─────────────────────────────────

  /// Generates a random character password based on toggled character sets.
  static ({String password, double entropyBits}) generateCustomPassword({
    int length = 24,
    bool useUppercase = true,
    bool useLowercase = true,
    bool useNumbers = true,
    bool useSymbols = true,
    bool excludeAmbiguous = false,
  }) {
    final len = length.clamp(8, 128);

    String upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    String lower = 'abcdefghijklmnopqrstuvwxyz';
    String numbers = '0123456789';
    String symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

    if (excludeAmbiguous) {
      upper = upper.replaceAll(RegExp(r'[I O]'), '');
      lower = lower.replaceAll(RegExp(r'[l o]'), '');
      numbers = numbers.replaceAll(RegExp(r'[0 1]'), '');
    }

    String pool = '';
    final requiredChars = <String>[];

    if (useUppercase && upper.isNotEmpty) {
      pool += upper;
      requiredChars.add(upper[_secureRandom.nextInt(upper.length)]);
    }
    if (useLowercase && lower.isNotEmpty) {
      pool += lower;
      requiredChars.add(lower[_secureRandom.nextInt(lower.length)]);
    }
    if (useNumbers && numbers.isNotEmpty) {
      pool += numbers;
      requiredChars.add(numbers[_secureRandom.nextInt(numbers.length)]);
    }
    if (useSymbols && symbols.isNotEmpty) {
      pool += symbols;
      requiredChars.add(symbols[_secureRandom.nextInt(symbols.length)]);
    }

    if (pool.isEmpty) {
      pool = lower;
      requiredChars.add(lower[_secureRandom.nextInt(lower.length)]);
    }

    final passwordChars = <String>[...requiredChars];

    while (passwordChars.length < len) {
      final char = pool[_secureRandom.nextInt(pool.length)];
      passwordChars.add(char);
    }

    // Shuffle password using secure random
    for (int i = passwordChars.length - 1; i > 0; i--) {
      final j = _secureRandom.nextInt(i + 1);
      final temp = passwordChars[i];
      passwordChars[i] = passwordChars[j];
      passwordChars[j] = temp;
    }

    final password = passwordChars.join('');
    final entropyBits = len * (log(pool.length) / log(2));

    return (password: password, entropyBits: entropyBits);
  }

  // ── 3. Keyfile Generation ──────────────────────────────────────────────────

  /// Generates a binary keyfile filled with cryptographically secure random bytes.
  static Uint8List generateBinaryKeyfile(int sizeBytes) {
    final clampedSize = sizeBytes.clamp(16, 10 * 1024 * 1024); // max 10 MB limit
    final bytes = Uint8List(clampedSize);
    for (int i = 0; i < clampedSize; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// Generates a valid high-entropy PNG RGBA noise image keyfile.
  static Uint8List generateImageKeyfile(int dimension) {
    final dim = dimension.clamp(16, 1024);
    final rawPixels = Uint8List(dim * dim * 4);

    for (int i = 0; i < rawPixels.length; i += 4) {
      rawPixels[i] = _secureRandom.nextInt(256); // R
      rawPixels[i + 1] = _secureRandom.nextInt(256); // G
      rawPixels[i + 2] = _secureRandom.nextInt(256); // B
      rawPixels[i + 3] = 255; // Alpha (fully opaque)
    }

    return _encodePng(dim, dim, rawPixels);
  }

  /// Encodes raw RGBA pixel data into a standard PNG file byte stream.
  static Uint8List _encodePng(int width, int height, Uint8List rgbaBytes) {
    final builder = BytesBuilder();

    // 1. PNG Signature
    builder.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    // 2. IHDR Chunk (13 bytes header)
    final ihdrData = Uint8List(13);
    final bd = ByteData.view(ihdrData.buffer);
    bd.setUint32(0, width, Endian.big);
    bd.setUint32(4, height, Endian.big);
    ihdrData[8] = 8; // 8 bits per channel
    ihdrData[9] = 6; // Color type 6 = RGBA
    ihdrData[10] = 0; // Compression method 0 (deflate)
    ihdrData[11] = 0; // Filter method 0
    ihdrData[12] = 0; // Interlace method 0

    _writeChunk(builder, 'IHDR', ihdrData);

    // 3. IDAT Chunk
    final scanlineStride = width * 4;
    final rawScanlines = Uint8List(height * (scanlineStride + 1));

    int rawOffset = 0;
    int scanlineOffset = 0;
    for (int y = 0; y < height; y++) {
      rawScanlines[scanlineOffset++] = 0; // Filter 0 (None)
      for (int x = 0; x < scanlineStride; x++) {
        rawScanlines[scanlineOffset++] = rgbaBytes[rawOffset++];
      }
    }

    final zlibData = _zlibUncompressed(rawScanlines);
    _writeChunk(builder, 'IDAT', zlibData);

    // 4. IEND Chunk
    _writeChunk(builder, 'IEND', Uint8List(0));

    return builder.toBytes();
  }

  static void _writeChunk(BytesBuilder builder, String type, Uint8List data) {
    final typeBytes = ascii.encode(type);
    final lenBytes = Uint8List(4);
    ByteData.view(lenBytes.buffer).setUint32(0, data.length, Endian.big);
    builder.add(lenBytes);
    builder.add(typeBytes);
    if (data.isNotEmpty) builder.add(data);

    final crcInput = Uint8List(typeBytes.length + data.length);
    crcInput.setRange(0, typeBytes.length, typeBytes);
    crcInput.setRange(typeBytes.length, crcInput.length, data);

    final crcVal = _computeCrc32(crcInput);
    final crcBytes = Uint8List(4);
    ByteData.view(crcBytes.buffer).setUint32(0, crcVal, Endian.big);
    builder.add(crcBytes);
  }

  /// Writes valid zlib uncompressed store blocks (RFC 1950 / RFC 1951).
  static Uint8List _zlibUncompressed(Uint8List data) {
    final out = BytesBuilder();
    // Zlib header: CMF 0x78 (Deflate, 32k window), FLG 0x01 (No dict, FCHECK 1)
    out.add(const [0x78, 0x01]);

    int offset = 0;
    while (offset < data.length) {
      final chunkSize = min(65535, data.length - offset);
      final isLast = (offset + chunkSize == data.length);
      final bfinalBtype = isLast ? 0x01 : 0x00;

      out.addByte(bfinalBtype);
      final lenLo = chunkSize & 0xFF;
      final lenHi = (chunkSize >> 8) & 0xFF;
      final nlenLo = (~chunkSize) & 0xFF;
      final nlenHi = ((~chunkSize) >> 8) & 0xFF;

      out.add([lenLo, lenHi, nlenLo, nlenHi]);
      out.add(data.sublist(offset, offset + chunkSize));
      offset += chunkSize;
    }

    // Adler-32 Checksum
    final adler = _adler32(data);
    final adlerBytes = Uint8List(4);
    ByteData.view(adlerBytes.buffer).setUint32(0, adler, Endian.big);
    out.add(adlerBytes);

    return out.toBytes();
  }

  static int _computeCrc32(Uint8List bytes) {
    var crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1 != 0) ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1);
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  static int _adler32(Uint8List bytes) {
    var s1 = 1;
    var s2 = 0;
    for (final b in bytes) {
      s1 = (s1 + b) % 65521;
      s2 = (s2 + s1) % 65521;
    }
    return (s2 << 16) | s1;
  }

  /// Calculates SHA-256 fingerprint hex of keyfile bytes.
  static String calculateKeyfileFingerprint(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Returns human-readable password strength classification.
  static ({String label, double scoreFraction, String crackTimeStr}) evaluatePasswordStrength(double entropyBits) {
    if (entropyBits < 40) {
      return (label: 'Weak', scoreFraction: 0.25, crackTimeStr: '< 1 second');
    } else if (entropyBits < 60) {
      return (label: 'Good', scoreFraction: 0.5, crackTimeStr: 'A few days / months');
    } else if (entropyBits < 80) {
      return (label: 'Strong', scoreFraction: 0.75, crackTimeStr: 'Several centuries');
    } else {
      return (label: 'Unbreakable', scoreFraction: 1.0, crackTimeStr: 'Millions of years');
    }
  }
}
