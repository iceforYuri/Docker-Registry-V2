// Package registry 包含了 Docker Registry 的核心领域模型，
// 如数据结构定义和业务相关的错误类型。
package registry

// Descriptor 描述了一个被引用的内容，是一个可复用组件
type Descriptor struct {
	MediaType string `json:"mediaType"`
	Size      int64  `json:"size"`
	Digest    string `json:"digest"`
	// Data 字段是 Manifest 中 config 描述符的一个可选字段。
	// 如果存在，它包含 base64 编码的配置 JSON。
	// omitempty 标签表示如果该字段为空，则在序列化为 JSON 时将其忽略。
	Data []byte `json:"data,omitempty"`
}

// Manifest 代表一个镜像的元数据，对应于 content type
// "application/vnd.docker.distribution.manifest.v2+json" 或 OCI 的
// "application/vnd.oci.image.manifest.v1+json"。
// 结构兼容
type Manifest struct {
	SchemaVersion int    `json:"schemaVersion"`
	MediaType     string `json:"mediaType"`

	// Config 描述了镜像的配置文件。
	Config Descriptor `json:"config"`

	// Layers 是一个有序列表，描述了构成镜像文件系统的各个层。
	Layers []Descriptor `json:"layers"`
}

// PlatformSpec 描述了一个 manifest 所适用的平台，包括操作系统和CPU架构。
type PlatformSpec struct {
	Architecture string `json:"architecture"`
	OS           string `json:"os"`
	// 还有其他可选字段，如 Variant, OSVersion, OSFeatures，为简化暂不包含
}

// ManifestDescriptor 在 Manifest List 中描述一个具体的 manifest 引用。
// 一个带有平台信息的 Descriptor。
type ManifestDescriptor struct {
	MediaType   string            `json:"mediaType"`
	Size        int64             `json:"size"`
	Digest      string            `json:"digest"`
	Platform    PlatformSpec      `json:"platform"`
	Annotations map[string]string `json:"annotations,omitempty"`
}

// ManifestList (也称为 Fat Manifest 或 Image Index) 是一个 manifest 的集合，
// 通常用于支持多架构镜像。它对应于 content type
// "application/vnd.docker.distribution.manifest.list.v2+json" 或 OCI 的
// "application/vnd.oci.image.index.v1+json"。
type ManifestList struct {
	SchemaVersion int    `json:"schemaVersion"`
	MediaType     string `json:"mediaType"`

	// Manifests 列出了该 tag 下所有可用的 manifest。
	// Docker 客户端会根据自身的平台选择合适的 manifest 进行拉取。
	Manifests []ManifestDescriptor `json:"manifests"`
}

// ImageConfig 定义了镜像 config blob 的 JSON 结构
type ImageConfig struct {
	OS           string `json:"os"`
	Architecture string `json:"architecture"`
}
