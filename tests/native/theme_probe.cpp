#include <QApplication>
#include <QFont>
#include <QPalette>
#include <QDockWidget>
#include <QListWidget>
#include <QMainWindow>
#include <QMenu>
#include <QPainter>
#include <QStyle>
#include <QTabWidget>
#include <iostream>

// Inspect the real platform theme, rather than parsing generated INI ourselves.
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    QMainWindow window;
    window.resize(780, 420);
    auto *tabs = new QTabWidget(&window);
    tabs->setDocumentMode(true);
    tabs->setTabsClosable(true);
    for (const auto &name : {"Home", "Documents", "Pictures"}) {
        auto *view = new QListWidget(tabs);
        view->setViewMode(QListView::IconMode);
        view->setIconSize(QSize(48, 48));
        view->setSpacing(20);
        view->setFrameStyle(QFrame::NoFrame);
        for (const auto &folder : {"Documents", "Downloads", "Pictures"}) {
            new QListWidgetItem(QIcon::fromTheme("folder"), folder, view);
        }
        tabs->addTab(view, name);
    }
    window.setCentralWidget(tabs);
    auto *dock = new QDockWidget("Places", &window);
    auto *places = new QListWidget(dock);
    places->addItems({"Home", "Desktop", "Documents", "Downloads", "Pictures", "Trash"});
    // KFilePlacesView uses a transparent viewport over QPalette::Window.
    places->setFrameStyle(QFrame::NoFrame);
    auto placePalette = places->palette();
    placePalette.setColor(QPalette::Base, placePalette.color(QPalette::Window));
    places->setPalette(placePalette);
    dock->setWidget(places);
    window.addDockWidget(Qt::LeftDockWidgetArea, dock);
    window.show();
    app.processEvents();
    QMenu menu(&window);
    menu.addAction("Open in New Tab");
    menu.addAction("Copy");
    menu.addAction("Properties");
    menu.popup(QPoint(430, 100));
    app.processEvents();
    auto popup = menu.grab().toImage();
    auto screenshot = window.grab().toImage();
    QPainter painter(&screenshot);
    painter.drawImage(QPoint(430, 100), popup);
    painter.end();
    if (argc > 1) screenshot.save(argv[1]);
    const auto palette = app.palette();
    std::cout << palette.color(QPalette::Window).name().toStdString() << "\n"
              << palette.color(QPalette::Base).name().toStdString() << "\n"
              << palette.color(QPalette::Highlight).name().toStdString() << "\n"
              << app.font().family().toStdString() << "\n"
              << app.font().pointSizeF() << "\n"
              << app.style()->objectName().toStdString() << "\n"
              << popup.pixelColor(popup.width() / 2, popup.height() - 10).name().toStdString() << "\n";
}
