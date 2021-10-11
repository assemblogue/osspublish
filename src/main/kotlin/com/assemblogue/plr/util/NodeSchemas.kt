/**
 * ノードスキーマ関連の定数です。
 *
 * @author <a href="mailto:m.ikemoto@runzan.co.jp">IKEMOTO, Masahiro</a>
 */
@file:JvmName("NodeSchemas")
package com.assemblogue.plr.util;

const val DEFAULT_CONTEXT = "http://www.assemblogue.com/plr/2.0/context.jsonld";

const val ID_ROOT = "";
const val ID_FORMAT = "%4d%02d%02d%02d%02d%02d_%s";

const val SYSTEM_PROP_PREFIX = "_";

// Classes.
const val CLASS_NODE = "Node";
const val CLASS_ACCOUNT = "Account";
const val CLASS_PERSON = "Person";
const val CLASS_TIMELINE = "Timeline";
const val CLASS_CHANNEL = "Channel";

const val CLASS_FRIEND_INFO = "FriendInfo";
const val CLASS_CHANNEL_INFO = "ChannelInfo";

const val CLASS_NOTIFICATION_REGISTRY = "NotificationRegistry";

const val CLASS_DATA_SETTINGS = "DataSettings";

const val CLASS_EVENT = "Event";
const val CLASS_RARE_EVENT = "RareEvent";

const val CLASS_NAME = "Name";
const val CLASS_PICTURE = "Picture";

const val CLASS_M = "M";

const val CLASS_OSS = "OSS";

const val CLASS_SCHEMA = "Schema";
const val CLASS_DATA_SETTING = "DataSetting";

const val CLASS_SELF_SCHEMA = "SelfSchema";
const val CLASS_GENERAL_SCHEMA = "GeneralSchema";

@JvmField
val CLASS_DEFAULT_PUBLIC_PROFILES = setOf(CLASS_NAME, CLASS_PICTURE);

@JvmField
val CLASS_EMBEDDED_SCHEMAS = setOf(CLASS_SELF_SCHEMA, CLASS_GENERAL_SCHEMA);

const val CLASS_REQUEST_RECEPTION = "RequestReception";

const val CLASS_DISCLOSURE_CONSENT_STORE = "DisclosureConsentStore";


// Properties
const val PROP_AT_CONTEXT = "@context";
const val PROP_AT_TYPE = "@type";
const val PROP_AT_ID = "@id";
const val PROP_AT_VALUE = "@value";
const val PROP_AT_GRAPH = "@graph";
const val PROP_INITIAL_ROOT = "initialRoot";
const val PROP_REMOVED = "removed";
const val PROP_KEY = "key";
const val PROP_KEY_ENCRYPTED = "keyEncrypted";
const val PROP_HAS_VERSION = "hasVersion";
const val PROP__USER_KEY = "_userKey";
const val PROP__DATA = "_data";
const val PROP_DATA = "data";
const val PROP_NET_DATA = "netData";
const val PROP_CACHE_DATA = "cacheData";

const val PROP_FORMAT = "format";
const val PROP_TITLE = "title";
const val PROP_COMMENT = "comment";
const val PROP_THUMBNAIL = "thumbnail";

const val PROP_BEGIN = "begin";
const val PROP_END = "end";
const val PROP_CREATOR = "creator";
const val PROP_IM = "im";

const val PROP_ITEM = "item";
const val PROP_DELETED = "deleted";
const val PROP_IS_SAME_TIMELINE_ITEM = "isSameTimelineItem";
const val PROP_TIMELINE_STATE = "timelineState";
const val PROP_PROHIBIT_EDITING = "prohibitEditing";

const val PROP_SUFFIX_SEPARATOR = ".";
const val PROP_LIFE_RECORD = "lifeRecord";
const val PROP_LIFE_RECORD_PREFIX =
	"${PROP_LIFE_RECORD}${PROP_SUFFIX_SEPARATOR}";
const val PROP_MESSAGING = "messaging";
const val PROP_MESSAGING_PREFIX = "${PROP_MESSAGING}${PROP_SUFFIX_SEPARATOR}";

const val PROP_FRIEND = "friend";
const val PROP_PUBLIC_FOLDER = "publicFolder";
const val PROP_PUBLIC_KEY = "publicKey";
const val PROP_ME_TO_FRIEND_ROOT = "meToFriendRoot";
const val PROP_FRIEND_TO_ME_ROOT_ID = "friendToMeRootId";

const val PROP_CHANNEL = "channel";
const val PROP_CHANNEL_PREFIX = "${PROP_CHANNEL}${PROP_SUFFIX_SEPARATOR}";
const val PROP_CHANNEL_ID = "channelId";
const val PROP_CHANNEL_INFO = "channelInfo";
const val PROP_NAME = "name";
const val PROP_DESCRIPTION = "description";

const val PROP_REFERENCED_CHANNEL = "referencedChannel";
const val PROP_REFERENCING_CHANNEL_INFO = "referencingChannelInfo";
const val PROP_DISCLOSE_TO_CHANNEL = "discloseToChannel";
const val PROP_PLR_ID = "plrId";
const val PROP_PUBLIC_ROOT = "publicRoot";

const val PROP_OSS = "oss";
const val PROP_ONTOLOGY = "ontology";
const val PROP_RESTRICTION = "restriction";
const val PROP_CONSTRAINT = "constraint";
const val PROP_TIMELINE_SS = "timelineSS";
const val PROP_CHANNEL_SS = "channelSS";
const val PROP_UNIT_TIME_SS = "unitTimeSS";
const val PROP_CHRONOLOGICAL_SS = "chronologicalSS";
const val PROP_SINGLE_CHANNEL_SS = "singleChannelSS";
const val PROP_OSS_ID = "ossId";
const val PROP_OSS_KIND = "ossKind";

const val PROP_REQUEST_RECEPTION = "requestReception";
const val PROP_FRIEND_REQUEST = "friendRequest";

const val PROP_DISCLOSURE_CONSENT = "disclosureConsent";
const val PROP_DISCLOSED_CHANNEL = "disclosedChannel";

const val PROP_DISCLOSURE_CONSENT_STORE = "disclosureConsentStore";
const val PROP_DISCLOSURE_CONSENT_SOURCE = "disclosureConsentSource";
const val PROP_DISCLOSURE_REQUEST = "disclosureRequest";
const val PROP_DISCLOSURE_REQUEST_SOURCE = "disclosureRequestSource";


/**
 * OSSを含む属性のセットです。
 */
@JvmField
val PROP_OSS_CONTAINERS = setOf(
	PROP_ONTOLOGY, PROP_RESTRICTION, PROP_CONSTRAINT, PROP_TIMELINE_SS, PROP_CHANNEL_SS,
	PROP_UNIT_TIME_SS, PROP_CHRONOLOGICAL_SS, PROP_SINGLE_CHANNEL_SS
);

const val PROP_NATIONAL_ID = "nationalID";
const val PROP_GENDER = "gender";
const val PROP_BIRTH = "birth";
const val PROP_DEATH = "death";
const val PROP_SPOUSE = "spouse";
const val PROP_PARENT = "parent";
const val PROP_CHILD = "child";
const val PROP_HOME = "home";
const val PROP_WORK = "work";
const val PROP_CUSTOMER = "customer";

const val PROP_FAMILY_NAME = "familyName";
const val PROP_MIDDLE_NAME = "middleName";
const val PROP_GIVEN_NAME = "givenName";

const val PROP_COUNTRY = "country";
const val PROP_POSTAL_CODE = "postalCode";
const val PROP_ADDRESS_REGION = "addressRegion";
const val PROP_ADDRESS_LOCALITY = "addressLocality";
const val PROP_STREET_ADDRESS = "streetAddress";
const val PROP_ROOM = "room";
const val PROP_TELEPHONE = "telephone";
const val PROP_FAX_NUMBER = "faxNumber";
const val PROP_EMAIL = "email";

const val PROP_LEGAL_NAME = "legalName";
const val PROP_POSITION = "position";

const val PROP_PICTURE = "picture";
const val PROP_CNT = "cnt";

const val PROP_MODEL = "model";
const val PROP_MODEL_ID = "modelId";
const val PROP_MODEL_KEY = "modelKey";
const val PROP_PARENT_ID = "parentId";
const val PROP_PARENT_MODEL = "parentModel";
const val PROP_PARENT_MODEL_ID = "parentModelId";
const val PROP_PARENT_MODEL_KEY = "parentModelKey";
const val PROP_REFERRED_PROPERTY_NAME = "referredPropertyName";

const val PROP_DISCLOSURE = "disclosure";
const val PROP_CONDITION = "condition";
const val PROP_DISCLOSED_BY = "disclosedBy";
const val PROP_SOURCE_NODE = "sourceNode";

const val PROP_CONSTITUENT = "constituent";
const val PROP_CONSTITUENT_OF = "constituentOf";

const val PROP_NEXT = "next";
const val PROP_PREV = "prev";

const val PROP_DATA_SETTING = "dataSetting";
const val PROP_DATA_SETTING_ID = "dataSettingId";
const val PROP_BODY = "body";
const val PROP_LINKS_AS = "linksAs";
const val PROP_NODE_TYPE = "nodeType";
const val PROP_INITIAL_ITEM = "initialItem";
const val PROP_SCHEMA = "schema";
const val PROP_GENERATED_FROM = "generatedFrom";
const val PROP_CHANNEL_DATA_SETTING = "channelDataSetting";
const val PROP_PARENT_PLR_ID = "parentPlrId";
const val PROP_PARENT_NODE = "parentNode";

const val PROP_DISCLOSED_TO_USER = "disclosedToUser";
const val PROP_DISCLOSED_TO_CHANNEL = "disclosedToChannel";
const val PROP_IS_DISCLOSED = "isDisclosed";

const val PROP_REFERRER = "referrer";
const val PROP_ENABLED = "enabled";
const val PROP_MODIFIED = "modified";
const val PROP_CHECKED = "checked";
const val PROP_CHANNEL_MODIFIED = "channelModified";
const val PROP_CHANNEL_CHECKED = "channelChecked";
const val PROP_TIMELINE_MODIFIED = "timelineModified";
const val PROP_TIMELINE_CHECKED = "timelineChecked";

/** 言語なし */
const val LANG_NONE = "";

/** 日本語 */
const val LANG_JA = "ja";

/**
 * ノードを含む属性のセットです。
 */
@JvmField
val PROP_CONTAINERS = setOf(PROP_HAS_VERSION, PROP_AT_GRAPH);

/**
 * 特殊な属性のセットです。
 */
@JvmField
val PROP_SPECIALS = PROP_CONTAINERS + PROP_AT_ID + PROP__USER_KEY;

/**
 * 暗号化しない属性のセットです。
 */
@JvmField
val PROP_NO_ENCRYPTS = PROP_SPECIALS + PROP_AT_CONTEXT;

/**
 * リストなどから除外する属性のセットです。
 */
@JvmField
val PROP_EXCLUDES = PROP_NO_ENCRYPTS + PROP_AT_TYPE;

/**
 * 構成素の親属性のリストです。
 */
@JvmField
val PROP_CONSTITUENT_OFS = listOf(PROP_CONSTITUENT_OF, PROP_PREV);

/**
 * 初期ルートノードの内容です。
 */
const val INITIAL_ROOT_NODE = """{"${PROP_AT_CONTEXT}":"${DEFAULT_CONTEXT}","${PROP_AT_ID}":"","${PROP_AT_TYPE}":"$CLASS_ACCOUNT","${PROP_INITIAL_ROOT}":true}""";

/**
 * 初期公開ルートノードの内容です。
 */
const val INITIAL_PUBLIC_ROOT_NODE = """{"${PROP_AT_CONTEXT}":"${DEFAULT_CONTEXT}","${PROP_AT_ID}":"","${PROP_AT_TYPE}":"${CLASS_NODE}"}""";

/**
 * 初期生活録ノードの内容です。
 */
const val INITIAL_LIFE_RECORD_NODE = """{"${PROP_AT_CONTEXT}":"${DEFAULT_CONTEXT}","${PROP_AT_ID}":"","${PROP_AT_TYPE}":"${CLASS_TIMELINE}"}""";

/**
 * デフォルトのOSSストレージです。
 */
const val DEFAULT_OSS_STORAGE = "googleDrive";

/**
 * デフォルトのOSSのフォーマットです。
 */
const val DEFAULT_OSS_FORMAT = "application/ld+json";

/**
 * 基本オントロジーです。
 */
@JvmField
val BASE_ONTOLOGY = arrayOf(
	"/1Pm-4-jymK_z4boAbvQoYDBQrYl1Iu8Io",
	"AES:6kEgMgPRdm6xkbfzBGXgDw==",
	"plr@assemblogue.com#bebf864fe47cca82#Base_ontology",
	"Base!", "基本!"
);

/**
 * プロフィールオントロジーです。
 */
@JvmField
val PROFILE_ONTOLOGY = arrayOf(
	"/1tTvmTEKFRmJai5tOcbaBhVgUuVbkOIe6",
	"AES:ZRzN4RvLbyr2d1cjNVt7wg==",
	"plr@assemblogue.com#3b4f49e8823164bc#Profile_ontology",
	"Profile", "プロフィール"
);

/**
 * 基本限定です。
 */
@JvmField
val BASE_RESTRICTION = arrayOf(
	"/1O2E2nkjlGQ0giSODR3unGyQg_tj5Z7Ky",
	"AES:BdA+BSlbMDkfzadiA/MYDA==",
	"plr@assemblogue.com#ff55d029c8d202c3#Base_restriction",
	"Base!", "基本!"
);

/**
 * プロフィール限定です。
 */
@JvmField
val PROFILE_RESTRICTION = arrayOf(
	"/1P25E-P3JxnIlWXdn9jqC5yw3E-9TiD2R",
	"AES:I7cmzAY/yq0txdWyFxk3vA==",
	"plr@assemblogue.com#a3e44b237ad8158f#Profile_restriction",
	"Profile", "プロフィール"
);

/**
 * デフォルトで適用されるオントロジーです。
 */
@JvmField
val DEFAULT_ONTOLOGY = arrayOf(BASE_ONTOLOGY);

/**
 * デフォルトで適用される限定です。
 */
@JvmField
val DEFAULT_RESTRICTION = arrayOf(BASE_RESTRICTION);

/**
 * 生活録の初期オントロジーです。
 */
@JvmField
val INITIAL_LIFE_RECORD_ONTOLOGY = arrayOf(BASE_ONTOLOGY, PROFILE_ONTOLOGY);

/**
 * 生活録の初期限定です。
 */
@JvmField
val INITIAL_LIFE_RECORD_RESTRICTION = arrayOf(
	BASE_RESTRICTION, PROFILE_RESTRICTION
);

/**
 * 初期通知レジストリノードの内容です。
 */
const val INITIAL_NOTIFICATION_REGISTRY_NODE = """{"${PROP_AT_CONTEXT}":"${DEFAULT_CONTEXT}","${PROP_AT_ID}":"","${PROP_AT_TYPE}":"${CLASS_NOTIFICATION_REGISTRY}"}""";

/**
 * 初期データ設定管理ノードの内容です。
 */
const val INITIAL_DATA_SETTINGS_NODE = """{"${PROP_AT_CONTEXT}":"${DEFAULT_CONTEXT}","${PROP_AT_ID}":"","${PROP_AT_TYPE}":"${CLASS_DATA_SETTINGS}"}""";

/**
 * 初期リクエスト受付ノードの内容です。
 */
const val INITIAL_REQUEST_RECEPTION_NODE = """{"${PROP_AT_CONTEXT}":"${DEFAULT_CONTEXT}","${PROP_AT_ID}":"","${PROP_AT_TYPE}":"${CLASS_REQUEST_RECEPTION}"}""";
