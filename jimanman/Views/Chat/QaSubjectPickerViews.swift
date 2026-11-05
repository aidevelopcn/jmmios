import SwiftUI

/// 答疑科目下拉（对齐 Android QaSubjectTrigger / QaSubjectDropdown）
struct QaSubjectPicker: View {
    let subjects: [String]
    let selected: String
    var counts: [String: Int] = [:]
    var otherDesc: String = "尚未归类的记录"
    var onSelect: (String) -> Void
    var onCreate: ((String) -> Void)? = nil
    var onDelete: ((String) -> Void)? = nil

    @State private var expanded = false
    @State private var search = ""

    private let brand = Color(hex: "00AFA4")
    private let field = Color(hex: "F3F6F8")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            trigger
            if expanded {
                menu
                    .padding(.top, 6)
            }
        }
    }

    private var trigger: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                expanded.toggle()
                if expanded { search = "" }
            }
        } label: {
            HStack(spacing: 6) {
                Text("科目：")
                    .font(.system(size: 14.5))
                    .foregroundColor(Color(hex: "64748B"))
                Text(selected)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(expanded ? Color(hex: "0F766E") : Color(hex: "0F172A"))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(expanded ? Color(hex: "0F766E") : Color(hex: "94A3B8"))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(expanded ? Color.white : field)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(expanded ? brand : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var keyword: String { search.trimmingCharacters(in: .whitespaces) }

    private var matched: [String] {
        subjects.filter { name in
            keyword.isEmpty
                || label(name).localizedCaseInsensitiveContains(keyword)
                || (isSystem(name) && otherDesc.localizedCaseInsensitiveContains(keyword))
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(hex: "94A3B8"))
                TextField("搜索或新建科目", text: $search)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Color(hex: "F1F5F9").frame(height: 1)
            if matched.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        section("快捷筛选", matched.filter { $0 == "全部" }, trash: false)
                        section("科目", matched.filter { !isSystem($0) && $0 != "全部" }, trash: onDelete != nil)
                        section("未分类", matched.filter { isSystem($0) && $0 != "全部" }, trash: false, muted: true)
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 262)
            }
        }
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "E2E8F0"), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(keyword.isEmpty ? "暂无科目" : "没有匹配「\(keyword)」的科目")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "64748B"))
            if let onCreate, !keyword.isEmpty, !isSystem(keyword) {
                Button("＋ 新建「\(keyword)」") {
                    expanded = false
                    onCreate(keyword)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(brand)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func section(_ title: String, _ names: [String], trash: Bool, muted: Bool = false) -> some View {
        Group {
            if !names.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "94A3B8"))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                ForEach(names, id: \.self) { name in
                    row(name, trash: trash && !isSystem(name), muted: muted)
                }
            }
        }
    }

    private func row(_ name: String, trash: Bool, muted: Bool) -> some View {
        let active = name == selected
        let count = counts[name]
        return HStack(spacing: 8) {
            Button {
                expanded = false
                onSelect(name)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(label(name))
                            .font(.system(size: 14, weight: active ? .semibold : .regular))
                            .foregroundColor(muted ? Color(hex: "64748B") : Color(hex: "0F172A"))
                        Spacer()
                        if let count {
                            Text("\(count)")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "94A3B8"))
                        }
                    }
                    if muted {
                        Text(otherDesc)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "94A3B8"))
                    }
                }
            }
            .buttonStyle(.plain)
            if trash {
                Button {
                    expanded = false
                    onDelete?(name)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "94A3B8"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(active ? brand.opacity(0.08) : Color.clear)
    }

    private func label(_ name: String) -> String {
        name == "其他科目" ? "其他科目" : name
    }

    private func isSystem(_ name: String) -> Bool {
        name == "全部" || name == "其他科目" || name == "未归类"
    }
}
