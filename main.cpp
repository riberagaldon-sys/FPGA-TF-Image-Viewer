#include <QApplication>
#include "mainwindow.h"

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("GX-BIDT 图片转换工具"));
    QApplication::setOrganizationName(QStringLiteral("GX-BIDT"));

    MainWindow w;
    w.show();
    return app.exec();
}
