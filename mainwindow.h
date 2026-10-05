#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QImage>
#include <QStringList>

class QListWidget;
class QLabel;
class QPushButton;
class QLineEdit;
class QComboBox;
class QCheckBox;
class QSpinBox;
class QSlider;
class QProgressBar;
class QDragEnterEvent;
class QDropEvent;

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);

protected:
    void dragEnterEvent(QDragEnterEvent *event) override;
    void dropEvent(QDropEvent *event) override;

private slots:
    void addImages();
    void removeSelected();
    void clearImages();
    void chooseOutputDirectory();
    void convertAll();
    void updatePreview();
    void openOutputDirectory();

private:
    enum FitMode {
        FitLetterbox = 0,
        FitCover = 1,
        FitStretch = 2
    };

    enum OutputFormat {
        OutputRgb666 = 0,
        OutputRgb565 = 1
    };

    static const int kWidth = 1024;
    static const int kHeight = 600;

    void buildUi();
    void applyStyle();
    void appendPaths(const QStringList &paths);
    QString currentPath() const;
    QImage loadImage(const QString &path, QString *error = nullptr) const;
    QImage prepareImage(const QImage &source) const;
    QImage applyClarity(const QImage &source, int amount) const;
    QImage makeHardwarePreview(const QImage &prepared) const;
    bool writeRgb666(const QImage &prepared, const QString &filePath, QString *error) const;
    bool writeRgb565(const QImage &prepared, const QString &filePath, QString *error) const;
    int quantize6(int value, int x, int y) const;
    QString outputName(int number) const;

    QListWidget *m_list = nullptr;
    QLabel *m_preview = nullptr;
    QLabel *m_infoLabel = nullptr;
    QLabel *m_countHint = nullptr;
    QLineEdit *m_outputEdit = nullptr;
    QComboBox *m_fitCombo = nullptr;
    QComboBox *m_formatCombo = nullptr;
    QCheckBox *m_rotatePortrait = nullptr;
    QCheckBox *m_dither = nullptr;
    QCheckBox *m_previewPng = nullptr;
    QCheckBox *m_clarityEnabled = nullptr;
    QSpinBox *m_startNumber = nullptr;
    QSlider *m_claritySlider = nullptr;
    QLabel *m_clarityValue = nullptr;
    QProgressBar *m_progress = nullptr;
    QPushButton *m_convertButton = nullptr;
};

#endif // MAINWINDOW_H
