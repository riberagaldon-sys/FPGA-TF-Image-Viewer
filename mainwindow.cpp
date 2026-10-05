#include "mainwindow.h"

#include <QAbstractItemView>
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDesktopServices>
#include <QDir>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QFormLayout>
#include <QFrame>
#include <QHBoxLayout>
#include <QImageReader>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QMessageBox>
#include <QMimeData>
#include <QPainter>
#include <QPixmap>
#include <QProgressBar>
#include <QPushButton>
#include <QScrollArea>
#include <QSlider>
#include <QSpinBox>
#include <QStandardPaths>
#include <QTextStream>
#include <QStringConverter>
#include <QTransform>
#include <QUrl>
#include <QVBoxLayout>
#include <QtGlobal>

namespace {
static inline int clamp8(int v)
{
    return v < 0 ? 0 : (v > 255 ? 255 : v);
}

static const int kBayer4[4][4] = {
    { 0,  8,  2, 10},
    {12,  4, 14,  6},
    { 3, 11,  1,  9},
    {15,  7, 13,  5}
};
}

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent)
{
    setAcceptDrops(true);
    buildUi();
    applyStyle();
    resize(1180, 760);
    setMinimumSize(980, 650);
}

void MainWindow::buildUi()
{
    setWindowTitle(QStringLiteral("GX-BIDT 1024×600 SD 图片转换工具"));

    QWidget *central = new QWidget(this);
    setCentralWidget(central);

    QVBoxLayout *root = new QVBoxLayout(central);
    root->setContentsMargins(18, 18, 18, 18);
    root->setSpacing(14);

    QLabel *title = new QLabel(QStringLiteral("SD 卡图片转换 · 1024×600 RGB 屏"), central);
    title->setObjectName(QStringLiteral("titleLabel"));
    QLabel *subtitle = new QLabel(
        QStringLiteral("批量导入 PNG / JPG / BMP，自动生成 PIC01.BIN、PIC02.BIN……；可直接把输出目录选为 SD 卡根目录。"),
        central);
    subtitle->setObjectName(QStringLiteral("subtitleLabel"));
    root->addWidget(title);
    root->addWidget(subtitle);

    QHBoxLayout *content = new QHBoxLayout;
    content->setSpacing(14);
    root->addLayout(content, 1);

    // Left: file queue
    QFrame *leftCard = new QFrame(central);
    leftCard->setObjectName(QStringLiteral("card"));
    QVBoxLayout *leftLayout = new QVBoxLayout(leftCard);
    leftLayout->setContentsMargins(14, 14, 14, 14);
    leftLayout->setSpacing(10);

    QLabel *listTitle = new QLabel(QStringLiteral("待转换图片"), leftCard);
    listTitle->setObjectName(QStringLiteral("sectionTitle"));
    leftLayout->addWidget(listTitle);

    m_list = new QListWidget(leftCard);
    m_list->setSelectionMode(QAbstractItemView::ExtendedSelection);
    m_list->setAlternatingRowColors(true);
    m_list->setMinimumWidth(310);
    leftLayout->addWidget(m_list, 1);

    QHBoxLayout *fileButtons = new QHBoxLayout;
    QPushButton *addButton = new QPushButton(QStringLiteral("+ 添加图片"), leftCard);
    QPushButton *removeButton = new QPushButton(QStringLiteral("删除选中"), leftCard);
    QPushButton *clearButton = new QPushButton(QStringLiteral("清空"), leftCard);
    fileButtons->addWidget(addButton);
    fileButtons->addWidget(removeButton);
    fileButtons->addWidget(clearButton);
    leftLayout->addLayout(fileButtons);

    m_countHint = new QLabel(QStringLiteral("0 张图片"), leftCard);
    m_countHint->setObjectName(QStringLiteral("hintLabel"));
    leftLayout->addWidget(m_countHint);
    content->addWidget(leftCard, 0);

    // Center: preview
    QFrame *previewCard = new QFrame(central);
    previewCard->setObjectName(QStringLiteral("card"));
    QVBoxLayout *previewLayout = new QVBoxLayout(previewCard);
    previewLayout->setContentsMargins(14, 14, 14, 14);
    previewLayout->setSpacing(10);
    QLabel *previewTitle = new QLabel(QStringLiteral("液晶屏效果预览"), previewCard);
    previewTitle->setObjectName(QStringLiteral("sectionTitle"));
    previewLayout->addWidget(previewTitle);

    m_preview = new QLabel(previewCard);
    m_preview->setAlignment(Qt::AlignCenter);
    m_preview->setMinimumSize(460, 270);
    m_preview->setText(QStringLiteral("添加图片后在这里预览\n最终 1024×600 显示效果"));
    m_preview->setObjectName(QStringLiteral("previewLabel"));
    previewLayout->addWidget(m_preview, 1);

    m_infoLabel = new QLabel(QStringLiteral("最终硬件帧缓存：RGB565；LCD 引脚输出：RGB888"), previewCard);
    m_infoLabel->setObjectName(QStringLiteral("hintLabel"));
    m_infoLabel->setWordWrap(true);
    previewLayout->addWidget(m_infoLabel);
    content->addWidget(previewCard, 1);

    // Right: settings
    QFrame *settingsCard = new QFrame(central);
    settingsCard->setObjectName(QStringLiteral("card"));
    settingsCard->setMinimumWidth(310);
    QVBoxLayout *settingsLayout = new QVBoxLayout(settingsCard);
    settingsLayout->setContentsMargins(14, 14, 14, 14);
    settingsLayout->setSpacing(10);

    QLabel *settingsTitle = new QLabel(QStringLiteral("转换设置"), settingsCard);
    settingsTitle->setObjectName(QStringLiteral("sectionTitle"));
    settingsLayout->addWidget(settingsTitle);

    QFormLayout *form = new QFormLayout;
    form->setLabelAlignment(Qt::AlignLeft | Qt::AlignVCenter);
    form->setHorizontalSpacing(10);
    form->setVerticalSpacing(10);

    m_startNumber = new QSpinBox(settingsCard);
    m_startNumber->setRange(1, 99);
    m_startNumber->setValue(1);
    form->addRow(QStringLiteral("起始编号"), m_startNumber);

    m_fitCombo = new QComboBox(settingsCard);
    m_fitCombo->addItem(QStringLiteral("保持比例 + 黑边"));
    m_fitCombo->addItem(QStringLiteral("居中裁切铺满"));
    m_fitCombo->addItem(QStringLiteral("拉伸到 1024×600"));
    m_fitCombo->setCurrentIndex(FitStretch);
    form->addRow(QStringLiteral("非 1024×600"), m_fitCombo);

    m_formatCombo = new QComboBox(settingsCard);
    m_formatCombo->addItem(QStringLiteral("RGB666 packed（当前工程兼容）"));
    m_formatCombo->addItem(QStringLiteral("RGB565 小端（体积更小）"));
    m_formatCombo->setCurrentIndex(OutputRgb666);
    form->addRow(QStringLiteral("BIN 格式"), m_formatCombo);

    m_rotatePortrait = new QCheckBox(QStringLiteral("竖图自动旋转为横屏"), settingsCard);
    m_rotatePortrait->setChecked(false);
    form->addRow(QString(), m_rotatePortrait);

    m_clarityEnabled = new QCheckBox(QStringLiteral("小字体清晰增强"), settingsCard);
    m_clarityEnabled->setChecked(true);
    form->addRow(QString(), m_clarityEnabled);

    QWidget *clarityWidget = new QWidget(settingsCard);
    QHBoxLayout *clarityLayout = new QHBoxLayout(clarityWidget);
    clarityLayout->setContentsMargins(0, 0, 0, 0);
    m_claritySlider = new QSlider(Qt::Horizontal, clarityWidget);
    m_claritySlider->setRange(0, 100);
    m_claritySlider->setValue(35);
    m_clarityValue = new QLabel(QStringLiteral("35"), clarityWidget);
    m_clarityValue->setFixedWidth(28);
    clarityLayout->addWidget(m_claritySlider, 1);
    clarityLayout->addWidget(m_clarityValue);
    form->addRow(QStringLiteral("增强强度"), clarityWidget);

    m_dither = new QCheckBox(QStringLiteral("有序抖动（照片可用，小字建议关闭）"), settingsCard);
    m_dither->setChecked(false);
    form->addRow(QString(), m_dither);

    m_previewPng = new QCheckBox(QStringLiteral("同时输出 PICxx_preview.png"), settingsCard);
    m_previewPng->setChecked(true);
    form->addRow(QString(), m_previewPng);

    settingsLayout->addLayout(form);

    QLabel *outLabel = new QLabel(QStringLiteral("输出目录 / SD 卡根目录"), settingsCard);
    outLabel->setObjectName(QStringLiteral("formLabel"));
    settingsLayout->addWidget(outLabel);

    QHBoxLayout *outLayout = new QHBoxLayout;
    m_outputEdit = new QLineEdit(settingsCard);
    m_outputEdit->setPlaceholderText(QStringLiteral("请选择输出目录"));
    QPushButton *browseButton = new QPushButton(QStringLiteral("浏览"), settingsCard);
    browseButton->setFixedWidth(68);
    outLayout->addWidget(m_outputEdit, 1);
    outLayout->addWidget(browseButton);
    settingsLayout->addLayout(outLayout);

    QPushButton *openButton = new QPushButton(QStringLiteral("打开输出目录"), settingsCard);
    settingsLayout->addWidget(openButton);
    settingsLayout->addStretch(1);

    m_progress = new QProgressBar(settingsCard);
    m_progress->setRange(0, 100);
    m_progress->setValue(0);
    settingsLayout->addWidget(m_progress);

    m_convertButton = new QPushButton(QStringLiteral("转换全部图片"), settingsCard);
    m_convertButton->setObjectName(QStringLiteral("primaryButton"));
    m_convertButton->setMinimumHeight(44);
    settingsLayout->addWidget(m_convertButton);
    content->addWidget(settingsCard, 0);

    connect(addButton, &QPushButton::clicked, this, &MainWindow::addImages);
    connect(removeButton, &QPushButton::clicked, this, &MainWindow::removeSelected);
    connect(clearButton, &QPushButton::clicked, this, &MainWindow::clearImages);
    connect(browseButton, &QPushButton::clicked, this, &MainWindow::chooseOutputDirectory);
    connect(openButton, &QPushButton::clicked, this, &MainWindow::openOutputDirectory);
    connect(m_convertButton, &QPushButton::clicked, this, &MainWindow::convertAll);
    connect(m_list, &QListWidget::currentRowChanged, this, &MainWindow::updatePreview);
    connect(m_fitCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &MainWindow::updatePreview);
    connect(m_rotatePortrait, &QCheckBox::toggled, this, &MainWindow::updatePreview);
    connect(m_dither, &QCheckBox::toggled, this, &MainWindow::updatePreview);
    connect(m_clarityEnabled, &QCheckBox::toggled, this, &MainWindow::updatePreview);
    connect(m_claritySlider, &QSlider::valueChanged, this, [this](int value) {
        m_clarityValue->setText(QString::number(value));
        updatePreview();
    });
}

void MainWindow::applyStyle()
{
    setStyleSheet(QStringLiteral(R"(
        QMainWindow { background: #f3f7fb; }
        QWidget { font-family: "Microsoft YaHei", "Segoe UI"; font-size: 13px; color: #203040; }
        QLabel#titleLabel { font-size: 24px; font-weight: 700; color: #0d5aa7; }
        QLabel#subtitleLabel { color: #60758a; padding-bottom: 4px; }
        QLabel#sectionTitle { font-size: 16px; font-weight: 700; color: #173d63; }
        QLabel#hintLabel { color: #71869a; }
        QLabel#formLabel { font-weight: 600; }
        QFrame#card { background: white; border: 1px solid #dce8f2; border-radius: 10px; }
        QListWidget { border: 1px solid #d7e3ee; border-radius: 7px; padding: 4px; background: #fbfdff; }
        QListWidget::item { min-height: 30px; padding: 3px; }
        QListWidget::item:selected { background: #dceeff; color: #114f85; border-radius: 5px; }
        QLabel#previewLabel { background: #101820; border: 1px solid #cad9e6; border-radius: 8px; color: #9eb3c5; }
        QPushButton { background: #edf5fb; border: 1px solid #c6d9ea; border-radius: 6px; padding: 7px 10px; }
        QPushButton:hover { background: #dfeefa; }
        QPushButton#primaryButton { background: #1477c9; color: white; border: none; font-weight: 700; font-size: 15px; }
        QPushButton#primaryButton:hover { background: #0f68b3; }
        QLineEdit, QComboBox, QSpinBox { min-height: 30px; border: 1px solid #cad8e4; border-radius: 5px; padding: 2px 6px; background: white; }
        QProgressBar { min-height: 18px; border: 1px solid #c9d7e3; border-radius: 5px; text-align: center; background: #eef3f7; }
        QProgressBar::chunk { background: #2f8ed5; border-radius: 4px; }
    )"));
}

void MainWindow::dragEnterEvent(QDragEnterEvent *event)
{
    if (event->mimeData()->hasUrls())
        event->acceptProposedAction();
}

void MainWindow::dropEvent(QDropEvent *event)
{
    QStringList paths;
    const QList<QUrl> urls = event->mimeData()->urls();
    for (const QUrl &url : urls) {
        const QString path = url.toLocalFile();
        const QString ext = QFileInfo(path).suffix().toLower();
        if (ext == QStringLiteral("png") || ext == QStringLiteral("jpg") ||
            ext == QStringLiteral("jpeg") || ext == QStringLiteral("bmp"))
            paths << path;
    }
    appendPaths(paths);
    event->acceptProposedAction();
}

void MainWindow::addImages()
{
    const QStringList files = QFileDialog::getOpenFileNames(
        this,
        QStringLiteral("选择图片"),
        QString(),
        QStringLiteral("图片 (*.png *.jpg *.jpeg *.bmp);;所有文件 (*.*)"));
    appendPaths(files);
}

void MainWindow::appendPaths(const QStringList &paths)
{
    for (const QString &path : paths) {
        bool exists = false;
        for (int i = 0; i < m_list->count(); ++i) {
            if (m_list->item(i)->data(Qt::UserRole).toString() == path) {
                exists = true;
                break;
            }
        }
        if (exists)
            continue;

        QFileInfo fi(path);
        QListWidgetItem *item = new QListWidgetItem(fi.fileName(), m_list);
        item->setData(Qt::UserRole, path);
        item->setToolTip(path);
    }

    m_countHint->setText(QStringLiteral("%1 张图片 · Vivado IMAGE_COUNT 建议设为 %1")
                         .arg(m_list->count()));
    if (m_list->count() > 0 && m_list->currentRow() < 0)
        m_list->setCurrentRow(0);
}

void MainWindow::removeSelected()
{
    const QList<QListWidgetItem*> items = m_list->selectedItems();
    for (QListWidgetItem *item : items)
        delete item;
    m_countHint->setText(QStringLiteral("%1 张图片 · Vivado IMAGE_COUNT 建议设为 %1")
                         .arg(m_list->count()));
    updatePreview();
}

void MainWindow::clearImages()
{
    m_list->clear();
    m_countHint->setText(QStringLiteral("0 张图片"));
    m_preview->setPixmap(QPixmap());
    m_preview->setText(QStringLiteral("添加图片后在这里预览\n最终 1024×600 显示效果"));
}

void MainWindow::chooseOutputDirectory()
{
    const QString dir = QFileDialog::getExistingDirectory(
        this,
        QStringLiteral("选择输出目录 / SD 卡根目录"),
        m_outputEdit->text());
    if (!dir.isEmpty())
        m_outputEdit->setText(QDir::toNativeSeparators(dir));
}

QString MainWindow::currentPath() const
{
    QListWidgetItem *item = m_list->currentItem();
    return item ? item->data(Qt::UserRole).toString() : QString();
}

QImage MainWindow::loadImage(const QString &path, QString *error) const
{
    QImageReader reader(path);
    reader.setAutoTransform(true);
    QImage image = reader.read();
    if (image.isNull() && error)
        *error = reader.errorString();
    return image;
}

QImage MainWindow::prepareImage(const QImage &source) const
{
    QImage image = source.convertToFormat(QImage::Format_RGB32);

    if (m_rotatePortrait->isChecked() && image.height() > image.width()) {
        QTransform t;
        t.rotate(90.0);
        image = image.transformed(t, Qt::SmoothTransformation);
    }

    const QSize target(kWidth, kHeight);
    if (image.size() != target) {
        if (m_fitCombo->currentIndex() == FitStretch) {
            image = image.scaled(target, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        } else if (m_fitCombo->currentIndex() == FitCover) {
            QImage scaled = image.scaled(target, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
            const int x = qMax(0, (scaled.width() - kWidth) / 2);
            const int y = qMax(0, (scaled.height() - kHeight) / 2);
            image = scaled.copy(x, y, kWidth, kHeight);
        } else {
            QImage scaled = image.scaled(target, Qt::KeepAspectRatio, Qt::SmoothTransformation);
            QImage canvas(target, QImage::Format_RGB32);
            canvas.fill(Qt::black);
            const int x = (kWidth - scaled.width()) / 2;
            const int y = (kHeight - scaled.height()) / 2;
            QPainter painter(&canvas);
            painter.drawImage(x, y, scaled);
            painter.end();
            image = canvas;
        }
    }

    if (m_clarityEnabled->isChecked() && m_claritySlider->value() > 0)
        image = applyClarity(image, m_claritySlider->value());

    return image.convertToFormat(QImage::Format_RGB32);
}

QImage MainWindow::applyClarity(const QImage &source, int amount) const
{
    const QImage src = source.convertToFormat(QImage::Format_RGB32);
    QImage dst = src;

    // amount=35 roughly corresponds to the mild native-image sharpening that
    // produced the clearest small text on the target panel without obvious halos.
    const double strength = (static_cast<double>(amount) / 100.0) * 0.55;
    const double contrast = 1.0 + (static_cast<double>(amount) / 100.0) * 0.10;

    for (int y = 1; y < src.height() - 1; ++y) {
        const QRgb *up = reinterpret_cast<const QRgb*>(src.constScanLine(y - 1));
        const QRgb *row = reinterpret_cast<const QRgb*>(src.constScanLine(y));
        const QRgb *down = reinterpret_cast<const QRgb*>(src.constScanLine(y + 1));
        QRgb *out = reinterpret_cast<QRgb*>(dst.scanLine(y));

        for (int x = 1; x < src.width() - 1; ++x) {
            const QRgb c = row[x];
            const QRgb l = row[x - 1];
            const QRgb r = row[x + 1];
            const QRgb u = up[x];
            const QRgb d = down[x];

            const int avgR = (qRed(l) + qRed(r) + qRed(u) + qRed(d)) / 4;
            const int avgG = (qGreen(l) + qGreen(r) + qGreen(u) + qGreen(d)) / 4;
            const int avgB = (qBlue(l) + qBlue(r) + qBlue(u) + qBlue(d)) / 4;

            int rr = qRound(qRed(c) + strength * (qRed(c) - avgR));
            int gg = qRound(qGreen(c) + strength * (qGreen(c) - avgG));
            int bb = qRound(qBlue(c) + strength * (qBlue(c) - avgB));

            rr = qRound((rr - 128) * contrast + 128);
            gg = qRound((gg - 128) * contrast + 128);
            bb = qRound((bb - 128) * contrast + 128);

            out[x] = qRgb(clamp8(rr), clamp8(gg), clamp8(bb));
        }
    }
    return dst;
}

int MainWindow::quantize6(int value, int x, int y) const
{
    int base = value >> 2;
    if (!m_dither->isChecked() || base >= 63)
        return base;

    const int remainder = value & 0x03;
    const int threshold = kBayer4[y & 3][x & 3] >> 2;
    if (remainder > threshold)
        ++base;
    return qMin(base, 63);
}

QImage MainWindow::makeHardwarePreview(const QImage &prepared) const
{
    QImage src = prepared.convertToFormat(QImage::Format_RGB32);
    QImage out(kWidth, kHeight, QImage::Format_RGB32);

    for (int y = 0; y < kHeight; ++y) {
        const QRgb *in = reinterpret_cast<const QRgb*>(src.constScanLine(y));
        QRgb *dst = reinterpret_cast<QRgb*>(out.scanLine(y));
        for (int x = 0; x < kWidth; ++x) {
            const int r6 = quantize6(qRed(in[x]), x, y);
            const int g6 = quantize6(qGreen(in[x]), x, y);
            const int b6 = quantize6(qBlue(in[x]), x, y);

            // Current stable FPGA build stores RGB565 internally even when the
            // input file is RGB666. Emulate that exact final panel color here.
            const int r5 = r6 >> 1;
            const int b5 = b6 >> 1;
            const int r8 = (r5 << 3) | (r5 >> 2);
            const int g8 = (g6 << 2) | (g6 >> 4);
            const int b8 = (b5 << 3) | (b5 >> 2);
            dst[x] = qRgb(r8, g8, b8);
        }
    }
    return out;
}

bool MainWindow::writeRgb666(const QImage &prepared, const QString &filePath, QString *error) const
{
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        if (error) *error = file.errorString();
        return false;
    }

    QImage src = prepared.convertToFormat(QImage::Format_RGB32);
    QByteArray buffer;
    buffer.reserve(kWidth * kHeight * 18 / 8);

    quint64 acc = 0;
    int nbits = 0;
    for (int y = 0; y < kHeight; ++y) {
        const QRgb *row = reinterpret_cast<const QRgb*>(src.constScanLine(y));
        for (int x = 0; x < kWidth; ++x) {
            const int r6 = quantize6(qRed(row[x]), x, y);
            const int g6 = quantize6(qGreen(row[x]), x, y);
            const int b6 = quantize6(qBlue(row[x]), x, y);
            const quint32 pixel = (static_cast<quint32>(r6) << 12) |
                                  (static_cast<quint32>(g6) << 6) |
                                  static_cast<quint32>(b6);
            acc |= (static_cast<quint64>(pixel) << nbits);
            nbits += 18;
            while (nbits >= 8) {
                buffer.append(static_cast<char>(acc & 0xff));
                acc >>= 8;
                nbits -= 8;
            }
        }
    }

    if (nbits != 0 || buffer.size() != (kWidth * kHeight * 18 / 8)) {
        if (error) *error = QStringLiteral("RGB666 打包长度异常");
        return false;
    }

    if (file.write(buffer) != buffer.size()) {
        if (error) *error = file.errorString();
        return false;
    }
    return true;
}

bool MainWindow::writeRgb565(const QImage &prepared, const QString &filePath, QString *error) const
{
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        if (error) *error = file.errorString();
        return false;
    }

    QImage src = prepared.convertToFormat(QImage::Format_RGB32);
    QByteArray buffer;
    buffer.resize(kWidth * kHeight * 2);
    char *out = buffer.data();
    int pos = 0;

    for (int y = 0; y < kHeight; ++y) {
        const QRgb *row = reinterpret_cast<const QRgb*>(src.constScanLine(y));
        for (int x = 0; x < kWidth; ++x) {
            const int r5 = qRed(row[x]) >> 3;
            const int g6 = qGreen(row[x]) >> 2;
            const int b5 = qBlue(row[x]) >> 3;
            const quint16 pixel = static_cast<quint16>((r5 << 11) | (g6 << 5) | b5);
            out[pos++] = static_cast<char>(pixel & 0xff);
            out[pos++] = static_cast<char>((pixel >> 8) & 0xff);
        }
    }

    if (file.write(buffer) != buffer.size()) {
        if (error) *error = file.errorString();
        return false;
    }
    return true;
}

QString MainWindow::outputName(int number) const
{
    return QStringLiteral("PIC%1.BIN").arg(number, 2, 10, QLatin1Char('0'));
}

void MainWindow::updatePreview()
{
    const QString path = currentPath();
    if (path.isEmpty())
        return;

    QString error;
    const QImage src = loadImage(path, &error);
    if (src.isNull()) {
        m_preview->setPixmap(QPixmap());
        m_preview->setText(QStringLiteral("读取失败：%1").arg(error));
        return;
    }

    const QImage prepared = prepareImage(src);
    const QImage preview = makeHardwarePreview(prepared);
    const QPixmap pixmap = QPixmap::fromImage(preview).scaled(
        m_preview->size() - QSize(14, 14), Qt::KeepAspectRatio, Qt::SmoothTransformation);
    m_preview->setText(QString());
    m_preview->setPixmap(pixmap);

    m_infoLabel->setText(QStringLiteral("原图 %1×%2 → 1024×600；预览已模拟当前 FPGA 的 RGB565 帧缓存最终颜色。")
                         .arg(src.width()).arg(src.height()));
}

void MainWindow::convertAll()
{
    if (m_list->count() == 0) {
        QMessageBox::information(this, QStringLiteral("提示"), QStringLiteral("请先添加图片。"));
        return;
    }

    QString outputDir = QDir::fromNativeSeparators(m_outputEdit->text().trimmed());
    if (outputDir.isEmpty()) {
        chooseOutputDirectory();
        outputDir = QDir::fromNativeSeparators(m_outputEdit->text().trimmed());
        if (outputDir.isEmpty())
            return;
    }

    const int start = m_startNumber->value();
    if (start + m_list->count() - 1 > 99) {
        QMessageBox::warning(this, QStringLiteral("编号超限"), QStringLiteral("PIC 编号不能超过 99。"));
        return;
    }

    QDir dir(outputDir);
    if (!dir.exists() && !dir.mkpath(QStringLiteral("."))) {
        QMessageBox::critical(this, QStringLiteral("错误"), QStringLiteral("无法创建输出目录。"));
        return;
    }

    m_convertButton->setEnabled(false);
    m_progress->setRange(0, m_list->count());
    m_progress->setValue(0);

    int converted = 0;
    for (int i = 0; i < m_list->count(); ++i) {
        QApplication::processEvents();
        const QString path = m_list->item(i)->data(Qt::UserRole).toString();
        QString error;
        const QImage source = loadImage(path, &error);
        if (source.isNull()) {
            QMessageBox::critical(this, QStringLiteral("转换失败"),
                                  QStringLiteral("%1\n%2").arg(path, error));
            break;
        }

        const QImage prepared = prepareImage(source);
        const int number = start + i;
        const QString binPath = dir.filePath(outputName(number));

        bool ok = false;
        if (m_formatCombo->currentIndex() == OutputRgb666)
            ok = writeRgb666(prepared, binPath, &error);
        else
            ok = writeRgb565(prepared, binPath, &error);

        if (!ok) {
            QMessageBox::critical(this, QStringLiteral("写入失败"),
                                  QStringLiteral("%1\n%2").arg(binPath, error));
            break;
        }

        if (m_previewPng->isChecked()) {
            const QImage preview = makeHardwarePreview(prepared);
            const QString previewPath = dir.filePath(
                QStringLiteral("PIC%1_preview.png").arg(number, 2, 10, QLatin1Char('0')));
            preview.save(previewPath, "PNG");
        }

        ++converted;
        m_progress->setValue(converted);
    }

    m_convertButton->setEnabled(true);

    if (converted == m_list->count()) {
        QFile hintFile(dir.filePath(QStringLiteral("Vivado_IMAGE_COUNT.txt")));
        if (hintFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream ts(&hintFile);
            ts.setEncoding(QStringConverter::Utf8);
            ts << "PIC01.BIN ~ PIC" << QStringLiteral("%1").arg(start + converted - 1, 2, 10, QLatin1Char('0')) << " 已生成。\n";
            ts << "当前批次数量：" << converted << "\n";
            ts << "若从 PIC01 开始且全部连续，请把 Vivado 顶层参数 IMAGE_COUNT 设置为 "
               << (start + converted - 1) << "。\n";
            ts << "自动播放：上键正序、下键逆序，每张完整显示 5 秒。\n";
        }

        QMessageBox::information(
            this,
            QStringLiteral("转换完成"),
            QStringLiteral("已生成 %1 张 BIN。\n\n输出目录：%2\n\nVivado IMAGE_COUNT：%3")
                .arg(converted)
                .arg(QDir::toNativeSeparators(outputDir))
                .arg(start + converted - 1));
    }
}

void MainWindow::openOutputDirectory()
{
    const QString path = QDir::fromNativeSeparators(m_outputEdit->text().trimmed());
    if (path.isEmpty())
        return;
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}
