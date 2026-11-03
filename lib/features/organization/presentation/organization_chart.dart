import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/organization_tree.dart';

class OrganizationChart extends StatefulWidget {
  const OrganizationChart({
    super.key,
    required this.profiles,
    required this.onOpenProfile,
  });
  final List<Map<String, dynamic>> profiles;
  final ValueChanged<Map<String, dynamic>> onOpenProfile;
  @override
  State<OrganizationChart> createState() => _OrganizationChartState();
}

class _OrganizationChartState extends State<OrganizationChart> {
  final _transform = TransformationController();
  String _search = '';
  String? _department;
  bool? _chart;
  String? _sceneKey;
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final tree = OrganizationTree(widget.profiles);
      final visible = tree.visible(_search, _department);
      final chart = _chart ?? box.maxWidth >= 720;
      final departments =
          tree.people.values
              .map((p) => '${p['department'] ?? ''}'.trim())
              .toSet()
              .toList()
            ..sort();
      final colors = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Organization chart',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${tree.people.length} employees · reporting relationships',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: math.min(340, box.maxWidth),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search name, department or role',
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
              ),
              SizedBox(
                width: math.min(260, box.maxWidth),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_department),
                  initialValue: _department,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('All departments'),
                    ),
                    for (final department in {
                      ...departments,
                      ?_department,
                    })
                      DropdownMenuItem(
                        value: department,
                        child: Text(
                          department.isEmpty ? 'No department' : department,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _department = value),
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.account_tree_outlined),
                    label: Text('Chart'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.format_list_bulleted),
                    label: Text('Outline'),
                  ),
                ],
                selected: {chart},
                onSelectionChanged: (value) =>
                    setState(() => _chart = value.first),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (tree.cycles.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Some reporting links form a cycle. Affected employees are shown separately for review.',
              ),
            ),
          if (_search.trim().isNotEmpty || _department != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Matching employees and their reporting managers are shown for context.',
              ),
            ),
          if (visible.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tree.people.isEmpty
                      ? 'No approved employees in this directory.'
                      : 'No employees match these filters.',
                ),
              ),
            )
          else if (chart)
            _canvas(tree, visible, box.maxWidth)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final id in tree.roots.where(visible.contains))
                  Card(child: _outline(tree, id, visible, 0)),
              ],
            ),
        ],
      );
    },
  );

  Widget _outline(
    OrganizationTree tree,
    String id,
    Set<String> visible,
    int depth,
  ) {
    final person = tree.people[id]!;
    final reports = (tree.children[id] ?? []).where(visible.contains).toList();
    final details = [
      for (final key in ['designation', 'department'])
        if (person[key]?.toString().trim().isNotEmpty == true)
          person[key].toString(),
    ].join(' · ');
    final subtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          details.isEmpty ? 'Profile details not set' : details,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (tree.note(id) != null)
          Text(tree.note(id)!, style: const TextStyle(fontSize: 11)),
        if (reports.isNotEmpty)
          Text(
            '${reports.length} direct reports shown',
            style: const TextStyle(fontSize: 11),
          ),
      ],
    );
    final avatar = CircleAvatar(
      child: Text(tree.name(id).characters.first.toUpperCase()),
    );
    if (reports.isEmpty) {
      return ListTile(
        leading: avatar,
        title: Text(tree.name(id)),
        subtitle: subtitle,
        onTap: () => widget.onOpenProfile(person),
      );
    }
    return ExpansionTile(
      key: PageStorageKey('organization-person:$id:$_search:$_department'),
      initiallyExpanded:
          depth == 0 || _search.trim().isNotEmpty || _department != null,
      leading: IconButton(
        tooltip: 'Open ${tree.name(id)} profile',
        onPressed: () => widget.onOpenProfile(person),
        icon: avatar,
      ),
      title: Text(tree.name(id)),
      subtitle: subtitle,
      childrenPadding: EdgeInsets.only(left: depth < 3 ? 12 : 0),
      children: [
        for (final child in reports) _outline(tree, child, visible, depth + 1),
      ],
    );
  }

  Widget _canvas(
    OrganizationTree tree,
    Set<String> visible,
    double viewportWidth,
  ) {
    const nodeWidth = 224.0, horizontalGap = 24.0, verticalGap = 56.0;
    final nodeHeight =
        156.0 +
        math.max(0.0, MediaQuery.textScalerOf(context).scale(14) - 14) * 4;
    final widths = <String, double>{};
    List<String> reports(String id) =>
        (tree.children[id] ?? []).where(visible.contains).toList();
    double measure(String id) {
      final children = reports(id);
      final width = children.isEmpty
          ? nodeWidth
          : math.max(
              nodeWidth,
              children.fold<double>(0, (sum, child) => sum + measure(child)) +
                  horizontalGap * (children.length - 1),
            );
      return widths[id] = width;
    }

    final roots = tree.roots.where(visible.contains).toList();
    final contentWidth =
        roots.fold<double>(0, (sum, root) => sum + measure(root)) +
        horizontalGap * (roots.length - 1);
    final sceneWidth = math.max(contentWidth + 32, viewportWidth);
    final nodes = <String, Rect>{};
    final links = <(String, String)>[];
    void place(String id, double left, int depth) {
      nodes[id] = Rect.fromLTWH(
        left + (widths[id]! - nodeWidth) / 2,
        16 + depth * (nodeHeight + verticalGap),
        nodeWidth,
        nodeHeight,
      );
      var childLeft = left;
      for (final child in reports(id)) {
        links.add((id, child));
        place(child, childLeft, depth + 1);
        childLeft += widths[child]! + horizontalGap;
      }
    }

    var left = (sceneWidth - contentWidth) / 2;
    for (final root in roots) {
      place(root, left, 0);
      left += widths[root]! + horizontalGap;
    }
    final sceneHeight =
        nodes.values.fold<double>(
          0,
          (bottom, rect) => math.max(bottom, rect.bottom),
        ) +
        16;
    final viewportHeight = (MediaQuery.sizeOf(context).height * 0.65).clamp(
      360.0,
      720.0,
    );
    void fit() {
      final scale = math.min(
        1.0,
        math.min(viewportWidth / sceneWidth, viewportHeight / sceneHeight),
      );
      _transform.value = Matrix4.identity()
        ..translateByDouble((viewportWidth - sceneWidth * scale) / 2, 0, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    }

    final signature =
        '${visible.join('|')}:$viewportWidth:$viewportHeight:$nodeHeight:$sceneWidth:$sceneHeight';
    if (_sceneKey != signature) {
      _sceneKey = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sceneKey == signature) fit();
      });
    }
    void zoom(double factor) {
      final current = _transform.value.getMaxScaleOnAxis();
      final target = (current * factor).clamp(0.05, 2.5);
      _transform.value = _transform.value.clone()
        ..scaleByDouble(target / current, target / current, 1, 1);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Drag to pan · zoom to explore'),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: () => zoom(0.8),
              icon: const Icon(Icons.remove),
            ),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: () => zoom(1.25),
              icon: const Icon(Icons.add),
            ),
            TextButton(onPressed: fit, child: const Text('Fit to view')),
            TextButton(
              onPressed: () => _transform.value = Matrix4.identity(),
              child: const Text('100%'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: viewportHeight,
            child: InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: 0.05,
              maxScale: 2.5,
              boundaryMargin: const EdgeInsets.all(100),
              trackpadScrollCausesScale: true,
              child: SizedBox(
                width: sceneWidth,
                height: sceneHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ReportingLines(
                          nodes,
                          links,
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    for (final entry in nodes.entries)
                      Positioned.fromRect(
                        rect: entry.value,
                        child: _personCard(tree, entry.key),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _personCard(OrganizationTree tree, String id) {
    final person = tree.people[id]!;
    final note = tree.note(id);
    return Card(
      key: ValueKey('org-card:$id'),
      margin: const EdgeInsets.all(2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpenProfile(person),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              CircleAvatar(
                radius: 18,
                child: Text(tree.name(id).characters.first.toUpperCase()),
              ),
              const SizedBox(height: 6),
              Tooltip(
                message: tree.name(id),
                child: Text(
                  tree.name(id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                OrganizationTree.text(
                  person['designation'],
                  'Designation not set',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                OrganizationTree.text(
                  person['department'],
                  'Department not set',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              if (note != null)
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportingLines extends CustomPainter {
  _ReportingLines(this.nodes, this.links, this.color);
  final Map<String, Rect> nodes;
  final List<(String, String)> links;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final (parent, child) in links) {
      final start = nodes[parent]!.bottomCenter, end = nodes[child]!.topCenter;
      final middle = (start.dy + end.dy) / 2;
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(start.dx, middle)
          ..lineTo(end.dx, middle)
          ..lineTo(end.dx, end.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ReportingLines old) => true;
}
