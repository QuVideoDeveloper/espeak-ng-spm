#import "espeak-ng/bundle.h"
#import "espeak-ng/espeak_ng.h"
#import <map>
#import <memory>
#import <string>
#import <vector>
#import "espeak-ng/speak_lib.h"
typedef char32_t Phoneme;
typedef std::map<Phoneme, std::vector<Phoneme> > PhonemeMap;


#define CLAUSE_INTONATION_FULL_STOP 0x00000000
#define CLAUSE_INTONATION_COMMA 0x00001000
#define CLAUSE_INTONATION_QUESTION 0x00002000
#define CLAUSE_INTONATION_EXCLAMATION 0x00003000

#define CLAUSE_TYPE_CLAUSE 0x00040000
#define CLAUSE_TYPE_SENTENCE 0x00080000

#define CLAUSE_PERIOD (40 | CLAUSE_INTONATION_FULL_STOP | CLAUSE_TYPE_SENTENCE)
#define CLAUSE_COMMA (20 | CLAUSE_INTONATION_COMMA | CLAUSE_TYPE_CLAUSE)
#define CLAUSE_QUESTION (40 | CLAUSE_INTONATION_QUESTION | CLAUSE_TYPE_SENTENCE)
#define CLAUSE_EXCLAMATION                                                     \
  (45 | CLAUSE_INTONATION_EXCLAMATION | CLAUSE_TYPE_SENTENCE)
#define CLAUSE_COLON (30 | CLAUSE_INTONATION_FULL_STOP | CLAUSE_TYPE_CLAUSE)
#define CLAUSE_SEMICOLON (30 | CLAUSE_INTONATION_COMMA | CLAUSE_TYPE_CLAUSE)
const NSErrorDomain EspeakErrorDomain = @"EspeakErrorDomain";

@implementation EspeakLib
+ (BOOL)ensureBundleInstalledInRoot:(NSURL*_Nonnull)root error:(NSError*_Nullable*_Nonnull)error {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSURL *dataRoot = [root URLByAppendingPathComponent:@"espeak-ng-data"];

  NSBundle *bundle = [NSBundle bundleWithPath:@"espeak-ng_data.bundle"];
  if (!bundle) bundle = [NSBundle bundleWithURL:[[NSBundle mainBundle] URLForResource:@"espeak-ng_data" withExtension:@"bundle"]];
  NSURL *bdl = [bundle resourceURL];


  NSURL *bundleCheckURL = [[bundle.resourceURL URLByAppendingPathComponent:@"phsource"] URLByAppendingPathComponent:@"phonemes"];
  NSDate *bundleDate = [[fm attributesOfItemAtPath:bundleCheckURL.path error:nil] objectForKey:NSFileModificationDate];
  NSDate *installDate = [[fm attributesOfItemAtPath:dataRoot.path error:nil] objectForKey:NSFileModificationDate];

  if (installDate && bundleDate && [bundleDate compare:installDate] == NSOrderedDescending) {
    [fm removeItemAtURL:dataRoot error:nil];
    NSLog(@"UPDATE DATA: %@ -> %@", installDate, bundleDate);
  }

  FILE *nullout = nil;
  if (![fm fileExistsAtPath:dataRoot.path]) {
    nullout = fopen("/dev/null", "w");

    if (![fm copyItemAtURL:[bdl URLByAppendingPathComponent:@"espeak-ng-data"] toURL:dataRoot error:error]) return NO;
    espeak_ng_InitializePath([root.path cStringUsingEncoding:NSUTF8StringEncoding]);
    NSString *ph_root = [bdl URLByAppendingPathComponent:@"phsource" isDirectory:YES].path;
    NSURL *dictbdl_root = [bdl URLByAppendingPathComponent:@"dictsource" isDirectory:YES];
    NSURL *dict_temp;
    NSString *dict_root = dictbdl_root.path;
    if ([fm fileExistsAtPath:[dictbdl_root URLByAppendingPathComponent:@"extra"].path]) {
      dict_temp = [[fm temporaryDirectory] URLByAppendingPathComponent:@"dictsource" isDirectory:YES];
      [fm removeItemAtURL:dict_temp error:nil];
      if (![fm copyItemAtURL:dictbdl_root toURL:dict_temp error:error]) return NO;
      NSArray<NSURL*> *extra_dicts = [fm contentsOfDirectoryAtURL:[dictbdl_root URLByAppendingPathComponent:@"extra"] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants error:error];
      if (!extra_dicts) return NO;
      for (NSURL *u in extra_dicts) {
        if (![fm copyItemAtURL:u toURL:[dict_temp URLByAppendingPathComponent:u.lastPathComponent] error:error]) return NO;
      }
      dict_root = dict_temp.path;
    }

    espeak_ng_STATUS res;
    char errorbuf[256];
    if ((res = espeak_ng_CompileIntonationPath([ph_root cStringUsingEncoding:NSUTF8StringEncoding], nil, nullout, nil)) != ENS_OK) {
      espeak_ng_GetStatusCodeMessage(res, errorbuf, sizeof(errorbuf));
      *error = [NSError errorWithDomain:EspeakErrorDomain code:res userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errorbuf] }];
      goto fail;
    }
    if ((res = espeak_ng_CompilePhonemeDataPath(22050, [ph_root cStringUsingEncoding:NSUTF8StringEncoding], nil, nullout, nil)) != ENS_OK) {
      espeak_ng_GetStatusCodeMessage(res, errorbuf, sizeof(errorbuf));
      *error = [NSError errorWithDomain:EspeakErrorDomain code:res userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errorbuf] }];
      goto fail;
    }

    NSArray<NSURL*>* dict_files = [fm contentsOfDirectoryAtURL:[NSURL fileURLWithPath:dict_root] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants error:error];
    if (!dict_files) return NO;
    NSMutableSet<NSString*>* dict_names = [NSMutableSet new];
    espeak_VOICE v;
    for (NSURL *u in dict_files) {
      NSArray<NSString*>* comps = [[u lastPathComponent] componentsSeparatedByString:@"_"];
      if (comps.count != 2) continue;
      if (![comps.lastObject isEqualToString:@"rules"]) continue;
      NSString *d = comps.firstObject;

      bzero(&v, sizeof(v));
      v.languages = [d cStringUsingEncoding:NSUTF8StringEncoding];
      if ((res = espeak_ng_SetVoiceByProperties(&v)) != ENS_OK) {
        espeak_ng_GetStatusCodeMessage(res, errorbuf, sizeof(errorbuf));
        *error = [NSError errorWithDomain:EspeakErrorDomain code:res userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errorbuf] }];
        goto fail;
      }
      if ((res = espeak_ng_CompileDictionary([[dict_root stringByAppendingString:@"/"] cStringUsingEncoding:NSUTF8StringEncoding], [d cStringUsingEncoding:NSUTF8StringEncoding], nullout, 0, nil)) != ENS_OK) {
        espeak_ng_GetStatusCodeMessage(res, errorbuf, sizeof(errorbuf));
        *error = [NSError errorWithDomain:EspeakErrorDomain code:res userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errorbuf] }];
        goto fail;
      }
    }
    fclose(nullout);
    if (dict_temp) [fm removeItemAtURL:dict_temp error:nil];
  }
  return YES;
fail:
  fclose(nullout);
  [fm removeItemAtURL:dataRoot error:nil];
  return NO;
}

struct eSpeakPhonemeConfig {
  std::string voice = "en-us";

  Phoneme period = '.';      // CLAUSE_PERIOD
  Phoneme comma = ',';       // CLAUSE_COMMA
  Phoneme question = '?';    // CLAUSE_QUESTION
  Phoneme exclamation = '!'; // CLAUSE_EXCLAMATION
  Phoneme colon = ':';       // CLAUSE_COLON
  Phoneme semicolon = ';';   // CLAUSE_SEMICOLON
  Phoneme space = ' ';

  // Remove language switch flags like "(en)"
  bool keepLanguageFlags = false;

  std::shared_ptr<PhonemeMap> phonemeMap;
};

void phonemize_eSpeak(std::string text,std::vector<std::vector<Phoneme> > &phonemes) {
//std::map<std::string, PhonemeMap> DEFAULT_PHONEME_MAP = {
//        {"pt-br", {{'c', {'k'}}}}};
  eSpeakPhonemeConfig config;
  auto voice = config.voice;
  int result = espeak_SetVoiceByName(voice.c_str());
  if (result != 0) {
    throw std::runtime_error("Failed to set eSpeak-ng voice");
  }

  std::shared_ptr<PhonemeMap> phonemeMap;
//  if (config.phonemeMap) {
//    phonemeMap = config.phonemeMap;
//  } else if (DEFAULT_PHONEME_MAP.count(voice) > 0) {
//    phonemeMap = std::make_shared<PhonemeMap>(DEFAULT_PHONEME_MAP[voice]);
//  }

  // Modified by eSpeak
  std::string textCopy(text);

  std::vector<Phoneme> *sentencePhonemes = nullptr;
  const char *inputTextPointer = textCopy.c_str();
  int terminator = 0;

  while (inputTextPointer != NULL) {
    // Modified espeak-ng API to get access to clause terminator
    std::string clausePhonemes(espeak_TextToPhonemesWithTerminator(
        (const void **)&inputTextPointer,
        /*textmode*/ espeakCHARS_AUTO,
        /*phonememode = IPA*/ 0x02, &terminator));

    // Decompose, e.g. "ç" -> "c" + "̧"
//    auto phonemesNorm = una::norm::to_nfd_utf8(clausePhonemes);
//    auto phonemesRange = una::ranges::utf8_view{phonemesNorm};

    if (!sentencePhonemes) {
      // Start new sentence
      phonemes.emplace_back();
      sentencePhonemes = &phonemes[phonemes.size() - 1];
    }

    // Maybe use phoneme map
    std::vector<Phoneme> mappedSentPhonemes;
//    if (phonemeMap) {
//      for (auto phoneme : phonemesRange) {
//        if (phonemeMap->count(phoneme) < 1) {
//          // No mapping for phoneme
//          mappedSentPhonemes.push_back(phoneme);
//        } else {
//          // Mapping for phoneme
//          auto mappedPhonemes = &(phonemeMap->at(phoneme));
//          mappedSentPhonemes.insert(mappedSentPhonemes.end(),
//                                    mappedPhonemes->begin(),
//                                    mappedPhonemes->end());
//        }
//      }
//    } else {
      // No phoneme map
      for (auto &min_phoneme: clausePhonemes)
          mappedSentPhonemes.emplace_back(min_phoneme);
//    }

    auto phonemeIter = mappedSentPhonemes.begin();
    auto phonemeEnd = mappedSentPhonemes.end();

    if (config.keepLanguageFlags) {
      // No phoneme filter
      sentencePhonemes->insert(sentencePhonemes->end(), phonemeIter,
                               phonemeEnd);
    } else {
      // Filter out (lang) switch (flags).
      // These surround words from languages other than the current voice.
      bool inLanguageFlag = false;

      while (phonemeIter != phonemeEnd) {
        if (inLanguageFlag) {
          if (*phonemeIter == ')') {
            // End of (lang) switch
            inLanguageFlag = false;
          }
        } else if (*phonemeIter == '(') {
          // Start of (lang) switch
          inLanguageFlag = true;
        } else {
          sentencePhonemes->push_back(*phonemeIter);
        }

        phonemeIter++;
      }
    }

    // Add appropriate punctuation depending on terminator type
    int punctuation = terminator & 0x000FFFFF;
    if (punctuation == CLAUSE_PERIOD) {
      sentencePhonemes->push_back(config.period);
    } else if (punctuation == CLAUSE_QUESTION) {
      sentencePhonemes->push_back(config.question);
    } else if (punctuation == CLAUSE_EXCLAMATION) {
      sentencePhonemes->push_back(config.exclamation);
    } else if (punctuation == CLAUSE_COMMA) {
      sentencePhonemes->push_back(config.comma);
      sentencePhonemes->push_back(config.space);
    } else if (punctuation == CLAUSE_COLON) {
      sentencePhonemes->push_back(config.colon);
      sentencePhonemes->push_back(config.space);
    } else if (punctuation == CLAUSE_SEMICOLON) {
      sentencePhonemes->push_back(config.semicolon);
      sentencePhonemes->push_back(config.space);
    }

    if ((terminator & CLAUSE_TYPE_SENTENCE) == CLAUSE_TYPE_SENTENCE) {
      // End of sentence
      sentencePhonemes = nullptr;
    }

  } // while inputTextPointer != NULL

} /* phonemize_eSpeak */
+ (NSString *)process_text:(NSString *)text_input out:(NSString *)out_phoneme{
    const char *text_input_string = [text_input UTF8String];
    std::string stdString(text_input_string);
    std::vector<std::vector<Phoneme> > phonemes;
    phonemize_eSpeak(stdString,phonemes);
    std::string phoneme_string32;
    for(auto &phoneme:phonemes[0]){
        char temp= static_cast<char>(phoneme);
        phoneme_string32+=phoneme;
    }
    out_phoneme = [NSString stringWithUTF8String:phoneme_string32.c_str()];
    return out_phoneme;
}
@end
